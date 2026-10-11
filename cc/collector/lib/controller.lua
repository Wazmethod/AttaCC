local config = require("lib.config")
local protocol = require("lib.protocol")
local io = require("lib.io")

local M = {}

-- Controller states are centralized here instead of being scattered as
-- anonymous string literals throughout the state machine.
local STATES = {
    BOOT = "BOOT",
    RUNNING = "RUNNING",
    OFFLINE = "OFFLINE",
    DEGRADED = "DEGRADED",
    MANUAL = "MANUAL",
    MANUAL_TOPOLOGY = "MANUAL_TOPOLOGY",
    AUTO_WAIT_RPM = "AUTO_WAIT_RPM",
    AUTO_TRANSFER = "AUTO_TRANSFER",
    AUTO_VERIFY = "AUTO_VERIFY",
    AUTO_RETRY_WAIT = "AUTO_RETRY_WAIT",
    ERROR = "ERROR",
}

M.STATES = STATES

local STATE_FILE = ".steamplant-controller.json"

local state = STATES.BOOT
local stateSince = protocol.now()
local stateReason = "boot"
local lastError = nil
local initialized = false

local deadline = nil
local rpmStableSince = nil
local verifyDeadline = nil

local armed = false
local plantOffline = false
local offlineSince = nil
local recoverySince = nil

local autoStartAt = nil
local autoAttempts = 0
local procedureOrigin = nil
local alternatorLatchUntil = nil

local eventSink = nil
local seen = {}
local SEEN_TTL_MS = 15000

local function emit(level, code, message)
    if eventSink then
        eventSink({
            type = "plant_event",
            level = level,
            code = code,
            message = message,
            timestamp = protocol.now(),
            source = "collector",
        })
    end
end

function M.setEventSink(fn)
    eventSink = fn
end

local function savePersistentState()
    local payload = {
        armed = armed,
    }

    local ok, encoded = pcall(textutils.serializeJSON, payload)
    if not ok or not encoded then return end

    local tmp = STATE_FILE .. ".new"
    local h = fs.open(tmp, "w")
    if not h then return end

    h.write(encoded)
    h.close()

    if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
    fs.move(tmp, STATE_FILE)
end

local function loadPersistentState()
    if not fs.exists(STATE_FILE) then return end

    local h = fs.open(STATE_FILE, "r")
    if not h then return end

    local raw = h.readAll()
    h.close()

    local ok, data = pcall(textutils.unserializeJSON, raw)
    if ok and type(data) == "table" and type(data.armed) == "boolean" then
        armed = data.armed
    end
end

loadPersistentState()

local function transition(newState, reason, err)
    local oldState = state

    state = newState
    stateSince = protocol.now()
    stateReason = reason or "-"
    lastError = err

    if oldState ~= newState then
        emit(
            newState == STATES.ERROR and "critical" or "info",
            "STATE_CHANGE",
            tostring(oldState) .. " -> " .. tostring(newState)
                .. (reason and (" : " .. tostring(reason)) or "")
        )
    end
end

function M.getState() return state end
function M.getError() return lastError end
function M.isArmed() return armed end
function M.isPlantOffline() return plantOffline end
function M.isInitialized() return initialized end

local function procedureActive()
    return state == STATES.AUTO_WAIT_RPM
        or state == STATES.AUTO_TRANSFER
        or state == STATES.AUTO_VERIFY
end

function M.isAutomatic()
    return procedureActive() or state == STATES.AUTO_RETRY_WAIT
end

local function clearProcedureTimers()
    deadline = nil
    rpmStableSince = nil
    verifyDeadline = nil
end

local function clearAlternatorLatch()
    alternatorLatchUntil = nil
end

local function stopBlackStartDrive()
    io.stopMotor()
    io.setGen(false)
end

-- Named topologies make the black-start procedure readable and avoid repeating
-- raw clutch manipulations all over the controller.
local TOPOLOGIES = {
    BLACK_START = {
        main = false,
        gen = true,
        alternator = false,
        motor = config.procedure.motorRPM,
    },
    TRANSFER = {
        main = true,
        gen = false,
        alternator = false,
        motor = 0,
    },
    RUNNING = {
        main = true,
        gen = false,
        alternator = true,
        motor = 0,
    },
    ALL_CUT = {
        main = false,
        gen = false,
        alternator = false,
        motor = 0,
    },
}

local function applyTopology(name)
    local topology = TOPOLOGIES[name]
    if not topology then
        return false, "Unknown topology: " .. tostring(name)
    end

    io.setMain(topology.main)
    io.setGen(topology.gen)
    io.setAlternator(topology.alternator)

    if topology.motor == 0 then
        local ok, err = io.stopMotor()
        if not ok then return false, err end
    elseif topology.motor then
        local ok, err = io.setMotorSpeed(topology.motor)
        if not ok then return false, err end
    end

    return true
end

local function latchAlternator(ms, announce)
    io.setAlternator(true)
    alternatorLatchUntil = protocol.now() + (ms or 3000)

    if announce then
        emit("info", "ALT_LATCH_START", "Alternator clutch asserted for startup transfer")
    end
end

local function classifyPhysical(power)
    local rpm = math.abs(power.rpm or 0)
    local capacity = power.capacity or 0

    if rpm >= config.detection.onlineRpm
        and capacity >= config.detection.onlineCapacity
    then
        return STATES.RUNNING
    end

    if rpm <= config.detection.offlineRpm
        and capacity <= config.detection.offlineCapacity
    then
        return STATES.OFFLINE
    end

    return STATES.DEGRADED
end

-- Called once after the first successful telemetry sample. This does not touch
-- any clutch or motor output: boot synchronization is observational only.
function M.initialize(power)
    if initialized then return state end

    local detected = classifyPhysical(power)
    initialized = true

    plantOffline = detected == STATES.OFFLINE
    offlineSince = plantOffline and protocol.now() or nil
    recoverySince = nil
    autoAttempts = 0
    procedureOrigin = nil
    clearProcedureTimers()
    clearAlternatorLatch()

    transition(detected, "physical state detected at boot")

    emit(
        "success",
        "CONTROLLER_INIT",
        "Controller synchronized from physical state: "
            .. detected
            .. " / AUTO "
            .. (armed and "ARMED" or "DISARMED")
    )

    if plantOffline and armed then
        autoStartAt = protocol.now() + config.procedure.autoRestartDelayMs
        emit("warning", "AUTO_RESTART_PENDING", "Plant offline at boot - automatic black-start scheduled")
    end

    return state
end

function M.getDebug()
    local now = protocol.now()

    return {
        now = now,
        initialized = initialized,
        state = state,
        stateReason = stateReason,
        stateSince = stateSince,
        stateAgeMs = now - stateSince,
        armed = armed,
        plantOffline = plantOffline,
        offlineSince = offlineSince,
        recoverySince = recoverySince,
        autoStartAt = autoStartAt,
        autoStartInMs = autoStartAt and (autoStartAt - now) or nil,
        autoAttempts = autoAttempts,
        procedureOrigin = procedureOrigin,
        deadline = deadline,
        deadlineInMs = deadline and (deadline - now) or nil,
        rpmStableSince = rpmStableSince,
        verifyDeadline = verifyDeadline,
        verifyInMs = verifyDeadline and (verifyDeadline - now) or nil,
        alternatorLatchUntil = alternatorLatchUntil,
        alternatorLatchInMs = alternatorLatchUntil and (alternatorLatchUntil - now) or nil,
        alternatorCommanded = io.alternatorEngaged(),
        mainCommanded = io.mainEngaged(),
        genCommanded = io.genEngaged(),
        lastError = lastError,
    }
end

local function scheduleRetry(reason)
    stopBlackStartDrive()
    clearProcedureTimers()

    if procedureOrigin == "automatic"
        and armed
        and plantOffline
        and autoAttempts < config.procedure.maxAutoAttempts
    then
        autoStartAt = protocol.now() + config.procedure.retryDelayMs
        transition(STATES.AUTO_RETRY_WAIT, reason, reason)

        emit(
            "warning",
            "AUTO_RETRY_PENDING",
            "Startup failed - retry "
                .. tostring(autoAttempts + 1)
                .. "/"
                .. tostring(config.procedure.maxAutoAttempts)
                .. " in "
                .. tostring(math.floor(config.procedure.retryDelayMs / 1000))
                .. "s"
        )
    else
        autoStartAt = nil
        transition(STATES.ERROR, reason, reason)
        emit("critical", "START_ERROR", reason)
    end
end

function M.setArmed(value)
    value = value and true or false

    if armed ~= value then
        armed = value
        savePersistentState()

        emit(
            "info",
            armed and "AUTO_ARMED" or "AUTO_DISARMED",
            armed and "Automatic restart armed" or "Automatic restart disarmed"
        )
    end

    if not armed then
        autoStartAt = nil

        if state == STATES.AUTO_RETRY_WAIT then
            transition(STATES.ERROR, "automatic restart disarmed", lastError)
        end

    elseif initialized
        and plantOffline
        and not M.isAutomatic()
        and state ~= STATES.ERROR
    then
        autoStartAt = protocol.now() + config.procedure.autoRestartDelayMs
        emit("warning", "AUTO_RESTART_PENDING", "Plant offline - automatic black-start scheduled")
    end

    return true
end

function M.startProcedure(origin)
    if not initialized then
        return false, "Controller not initialized"
    end

    procedureOrigin = origin or "manual"
    lastError = nil
    autoStartAt = nil
    recoverySince = nil
    clearAlternatorLatch()

    if procedureOrigin == "automatic" then
        autoAttempts = autoAttempts + 1
        emit(
            "warning",
            "AUTO_RESTART_BEGIN",
            "Automatic black-start attempt "
                .. tostring(autoAttempts)
                .. "/"
                .. tostring(config.procedure.maxAutoAttempts)
        )
    else
        emit("warning", "START_BEGIN", "Manual black-start started")
    end

    local ok, err = applyTopology("BLACK_START")
    if not ok then
        scheduleRetry("Black-start topology failed: " .. tostring(err))
        return false, lastError
    end

    deadline = protocol.now() + config.procedure.timeoutMs
    rpmStableSince = nil
    verifyDeadline = nil

    transition(STATES.AUTO_WAIT_RPM, "waiting for startup RPM")
    return true
end

function M.abortProcedure()
    stopBlackStartDrive()
    clearProcedureTimers()
    clearAlternatorLatch()
    autoStartAt = nil
    procedureOrigin = nil

    transition(classifyPhysical({
        rpm = io.getSpeed() or 0,
        capacity = io.call("stressometer", "getStressCapacity", 0) or 0,
    }), "startup procedure aborted")

    emit("warning", "AUTO_ABORTED", "Startup procedure aborted")
    return true
end

local function stepWaitRpm()
    if deadline and protocol.now() > deadline then
        scheduleRetry("Timeout waiting for startup RPM")
        return
    end

    local rpm = math.abs(io.getSpeed() or 0)

    if rpm < config.procedure.minRPM then
        rpmStableSince = nil
        return
    end

    if not rpmStableSince then
        rpmStableSince = protocol.now()
        return
    end

    if protocol.now() - rpmStableSince < config.procedure.stableMs then
        return
    end

    emit("info", "RPM_STABLE", "Startup rotation stable - transferring to steam drive")

    local ok, err = applyTopology("TRANSFER")
    if not ok then
        scheduleRetry("Transfer topology failed: " .. tostring(err))
        return
    end

    transition(STATES.AUTO_TRANSFER, "steam takeover transfer")
end

local function stepTransfer()
    if protocol.now() - stateSince < config.procedure.transferDelayMs then
        return
    end

    local ok, err = applyTopology("RUNNING")
    if not ok then
        scheduleRetry("Running topology failed: " .. tostring(err))
        return
    end

    latchAlternator(5000, true)
    verifyDeadline = protocol.now() + config.procedure.verifyRunningMs

    transition(STATES.AUTO_VERIFY, "final topology applied")
    emit("info", "AUTO_VERIFY", "Transfer complete - alternator engaged, verifying physical plant rotation")
end

local function stepVerify()
    -- Keep the final topology asserted while the kinetic network settles.
    io.setMain(true)
    io.setGen(false)
    latchAlternator(5000, false)
    io.stopMotor()

    if verifyDeadline and protocol.now() > verifyDeadline then
        scheduleRetry("Transfer completed but plant never reached RUNNING telemetry")
    end
end

local PROCEDURE_STEPS = {
    [STATES.AUTO_WAIT_RPM] = stepWaitRpm,
    [STATES.AUTO_TRANSFER] = stepTransfer,
    [STATES.AUTO_VERIFY] = stepVerify,
}

function M.update()
    if not initialized then return end

    if alternatorLatchUntil then
        if protocol.now() < alternatorLatchUntil then
            io.setAlternator(true)
        else
            alternatorLatchUntil = nil
        end
    end

    if autoStartAt
        and armed
        and plantOffline
        and protocol.now() >= autoStartAt
        and not procedureActive()
    then
        autoStartAt = nil
        M.startProcedure("automatic")
        return
    end

    local step = PROCEDURE_STEPS[state]
    if step then step() end
end

function M.updateDetection(power)
    if not initialized then return end

    local rpm = math.abs(power.rpm or 0)
    local capacity = power.capacity or 0

    local offlineNow =
        rpm <= config.detection.offlineRpm
        and capacity <= config.detection.offlineCapacity

    local onlineNow =
        rpm >= config.detection.onlineRpm
        and capacity >= config.detection.onlineCapacity

    if state == STATES.AUTO_VERIFY and onlineNow then
        local ok, err = applyTopology("RUNNING")
        if not ok then
            scheduleRetry("Final running topology failed: " .. tostring(err))
            return
        end

        latchAlternator(5000, false)
        clearProcedureTimers()

        plantOffline = false
        offlineSince = nil
        recoverySince = nil
        autoStartAt = nil
        autoAttempts = 0
        procedureOrigin = nil

        transition(STATES.RUNNING, "physical RUNNING confirmed")

        emit(
            io.alternatorEngaged() and "success" or "warning",
            io.alternatorEngaged() and "ALTERNATOR_ENGAGED" or "ALTERNATOR_NOT_ENGAGED",
            io.alternatorEngaged()
                and "Alternator clutch engaged after startup"
                or "Alternator clutch command issued but output still reports CUT"
        )

        emit("success", "PLANT_RUNNING", "Steam plant physically confirmed RUNNING")
        return
    end

    if offlineNow then
        recoverySince = nil

        if not offlineSince then
            offlineSince = protocol.now()
        end

        if not plantOffline
            and protocol.now() - offlineSince >= config.detection.offlineConfirmMs
        then
            plantOffline = true
            autoAttempts = 0

            if not procedureActive() then
                transition(STATES.OFFLINE, "physical outage confirmed")
            end

            emit(
                "critical",
                "PLANT_OFFLINE",
                armed
                    and "Steam plant offline - AUTO RESTART ARMED"
                    or "Steam plant offline - auto restart disarmed"
            )

            if armed and not M.isAutomatic() then
                autoStartAt = protocol.now() + config.procedure.autoRestartDelayMs
                emit("warning", "AUTO_RESTART_PENDING", "Automatic black-start scheduled")
            end
        end

        return
    end

    offlineSince = nil

    if plantOffline and onlineNow then
        if procedureActive() then
            recoverySince = nil
            return
        end

        if not recoverySince then
            recoverySince = protocol.now()
            return
        end

        if protocol.now() - recoverySince >= config.detection.recoveryConfirmMs then
            plantOffline = false
            recoverySince = nil
            autoStartAt = nil
            autoAttempts = 0

            transition(STATES.RUNNING, "physical recovery confirmed")
            emit("success", "PLANT_RECOVERED", "Steam plant physically running")
        end

        return
    end

    recoverySince = nil

    if not procedureActive() and not plantOffline then
        local physical = classifyPhysical(power)

        if physical == STATES.DEGRADED
            and state ~= STATES.MANUAL
            and state ~= STATES.MANUAL_TOPOLOGY
            and state ~= STATES.ERROR
        then
            transition(STATES.DEGRADED, "physical state degraded")
        elseif physical == STATES.RUNNING
            and state == STATES.DEGRADED
        then
            transition(STATES.RUNNING, "physical state recovered")
        end
    end
end

local function enterManual(reason)
    clearProcedureTimers()
    clearAlternatorLatch()
    autoStartAt = nil
    procedureOrigin = nil
    stopBlackStartDrive()
    transition(STATES.MANUAL, reason or "manual command")
end

local function execute(msg)
    local cmd = msg.command

    if cmd == "procedure" then
        return M.startProcedure("manual")

    elseif cmd == "abort" then
        return M.abortProcedure()

    elseif cmd == "arm" then
        return M.setArmed(true)

    elseif cmd == "disarm" then
        return M.setArmed(false)

    elseif cmd == "main_on" then
        enterManual("MAIN manual command")
        io.setMain(true)
        return true

    elseif cmd == "main_off" then
        enterManual("MAIN manual command")
        io.setMain(false)
        return true

    elseif cmd == "alt_on" then
        enterManual("ALT manual command")
        io.setAlternator(true)
        return true

    elseif cmd == "alt_off" then
        enterManual("ALT manual command")
        io.setAlternator(false)
        return true

    elseif cmd == "gen_on" then
        enterManual("GEN manual command")
        io.setGen(true)
        return true

    elseif cmd == "gen_off" then
        enterManual("GEN manual command")
        io.setGen(false)
        return true

    elseif cmd == "motor_stop" then
        enterManual("motor stop")
        return io.stopMotor()

    elseif cmd == "motor_speed" then
        enterManual("motor speed")

        local rpm = tonumber(msg.rpm)
        if not rpm then return false, "Invalid RPM" end

        if rpm == 0 then
            return io.stopMotor()
        end

        return io.setMotorSpeed(rpm)

    elseif cmd == "running_topology" then
        clearProcedureTimers()
        clearAlternatorLatch()
        autoStartAt = nil
        procedureOrigin = nil

        local ok, err = applyTopology("RUNNING")
        if not ok then return false, err end

        transition(STATES.MANUAL_TOPOLOGY, "running topology requested")
        emit("info", "TOPOLOGY_SET", "Running topology applied - physical RUNNING remains telemetry-driven")
        return true

    elseif cmd == "all_cut" then
        enterManual("all cut")
        return applyTopology("ALL_CUT")
    end

    return false, "Unknown command: " .. tostring(cmd)
end

local function cleanupSeen()
    local now = protocol.now()

    for id, ts in pairs(seen) do
        if now - ts > SEEN_TTL_MS then
            seen[id] = nil
        end
    end
end

function M.handleCommand(modem, msg)
    if type(msg) ~= "table" or msg.target ~= "steam_plant" then return end

    cleanupSeen()

    if msg.id and seen[msg.id] then
        modem.transmit(config.channels.ack, config.channels.ack, {
            type = "command_ack",
            id = msg.id,
            command = msg.command,
            ok = true,
            duplicate = true,
        })
        return
    end

    local ok, err = execute(msg)

    if msg.id and ok then
        seen[msg.id] = protocol.now()
    end

    if msg.id then
        modem.transmit(config.channels.ack, config.channels.ack, {
            type = "command_ack",
            id = msg.id,
            command = msg.command,
            ok = ok and true or false,
            error = err,
        })
    end
end

return M
