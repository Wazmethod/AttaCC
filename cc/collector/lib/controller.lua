local config = require("lib.config")
local protocol = require("lib.protocol")
local io = require("lib.io")

local M = {}

local state = "MANUAL"
local lastError = nil
local stateSince = protocol.now()

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

-- Keep the alternator clutch asserted for a short period after transfer.
-- This protects against Create/CC redstone/peripheral state settling during
-- the kinetic topology change without fighting later manual commands.
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

local function setState(newState, err)
    state = newState
    stateSince = protocol.now()
    lastError = err
end

function M.getState() return state end
function M.getError() return lastError end
function M.isArmed() return armed end
function M.isPlantOffline() return plantOffline end

local function procedureActive()
    return state == "AUTO_WAIT_RPM"
        or state == "AUTO_TRANSFER"
        or state == "AUTO_VERIFY"
end

function M.isAutomatic()
    return procedureActive()
        or state == "AUTO_RETRY_WAIT"
end

local function clearProcedureTimers()
    deadline = nil
    rpmStableSince = nil
    verifyDeadline = nil
end

local function clearAlternatorLatch()
    alternatorLatchUntil = nil
end

local function latchAlternator(ms)
    io.setAlternator(true)
    alternatorLatchUntil = protocol.now() + (ms or 3000)
end

local function stopBlackStartDrive()
    io.stopMotor()
    io.setGen(false)
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
        setState("AUTO_RETRY_WAIT", reason)

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
        setState("ERROR", reason)
        emit("critical", "START_ERROR", reason)
    end
end

function M.setArmed(value)
    value = value and true or false

    if armed ~= value then
        armed = value
        emit(
            "info",
            armed and "AUTO_ARMED" or "AUTO_DISARMED",
            armed and "Automatic restart armed" or "Automatic restart disarmed"
        )
    end

    if not armed then
        autoStartAt = nil
        if state == "AUTO_RETRY_WAIT" then
            setState("ERROR", lastError or "Automatic restart disarmed")
        end
    elseif plantOffline
        and not M.isAutomatic()
        and state ~= "ERROR"
    then
        autoStartAt = protocol.now() + config.procedure.autoRestartDelayMs
        emit("warning", "AUTO_RESTART_PENDING", "Plant offline - automatic restart scheduled")
    end

    return true
end

function M.startProcedure(origin)
    procedureOrigin = origin or "manual"
    lastError = nil
    autoStartAt = nil

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

    io.setMain(false)
    io.setAlternator(false)
    io.setGen(true)

    local ok, err = io.setMotorSpeed(config.procedure.motorRPM)
    if not ok then
        scheduleRetry("Motor setSpeed failed: " .. tostring(err))
        return false, lastError
    end

    deadline = protocol.now() + config.procedure.timeoutMs
    rpmStableSince = nil
    verifyDeadline = nil

    setState("AUTO_WAIT_RPM")
    return true
end

function M.abortProcedure()
    stopBlackStartDrive()
    clearProcedureTimers()
    clearAlternatorLatch()
    autoStartAt = nil
    procedureOrigin = nil

    setState("MANUAL")
    emit("warning", "AUTO_ABORTED", "Startup procedure aborted")
    return true
end

function M.update()
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

    if state == "AUTO_WAIT_RPM" then
        if deadline and protocol.now() > deadline then
            scheduleRetry("Timeout waiting for startup RPM")
            return
        end

        local rpm = math.abs(io.getSpeed() or 0)

        if rpm >= config.procedure.minRPM then
            if not rpmStableSince then
                rpmStableSince = protocol.now()
            elseif protocol.now() - rpmStableSince >= config.procedure.stableMs then
                emit("info", "RPM_STABLE", "Startup rotation stable - transferring to steam drive")
                io.setMain(true)
                io.setGen(false)
                io.stopMotor()
                setState("AUTO_TRANSFER")
            end
        else
            rpmStableSince = nil
        end

    elseif state == "AUTO_TRANSFER" then
        if protocol.now() - stateSince >= config.procedure.transferDelayMs then
            -- Final running topology after steam takeover:
            -- MAIN engaged, GEN cut, motor stopped, ALT engaged.
            io.setMain(true)
            io.setGen(false)
            io.stopMotor()
            latchAlternator(5000)

            verifyDeadline = protocol.now() + config.procedure.verifyRunningMs
            setState("AUTO_VERIFY")
            emit("info", "AUTO_VERIFY", "Transfer complete - alternator engaged, verifying physical plant rotation")
        end

    elseif state == "AUTO_VERIFY" then
        -- Belt-and-braces: keep the final topology asserted while verifying.
        io.setMain(true)
        io.setGen(false)
        latchAlternator(5000)
        io.stopMotor()

        if verifyDeadline and protocol.now() > verifyDeadline then
            scheduleRetry("Transfer completed but plant never reached RUNNING telemetry")
        end
    end
end

function M.updateDetection(power)
    local rpm = math.abs(power.rpm or 0)
    local capacity = power.capacity or 0

    local offlineNow =
        rpm <= config.detection.offlineRpm
        and capacity <= config.detection.offlineCapacity

    local onlineNow =
        rpm >= config.detection.onlineRpm
        and capacity >= config.detection.onlineCapacity

    if state == "AUTO_VERIFY" and onlineNow then
        -- Re-assert final running topology before declaring success.
        io.setMain(true)
        io.setGen(false)
        latchAlternator(5000)
        io.stopMotor()
        clearProcedureTimers()

        plantOffline = false
        offlineSince = nil
        recoverySince = nil
        autoStartAt = nil
        autoAttempts = 0
        procedureOrigin = nil

        setState("RUNNING")
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
    else
        offlineSince = nil

        if plantOffline and onlineNow then
            if not recoverySince then
                recoverySince = protocol.now()
            end

            if protocol.now() - recoverySince >= config.detection.recoveryConfirmMs then
                plantOffline = false
                recoverySince = nil
                autoStartAt = nil
                autoAttempts = 0

                if state ~= "AUTO_VERIFY" then
                    setState("RUNNING")
                end

                emit("success", "PLANT_RECOVERED", "Steam plant physically running")
            end
        elseif plantOffline then
            recoverySince = nil
        end
    end
end

local function manual()
    clearProcedureTimers()
    clearAlternatorLatch()
    autoStartAt = nil
    procedureOrigin = nil
    stopBlackStartDrive()
    setState("MANUAL")
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
        manual(); io.setMain(true); return true
    elseif cmd == "main_off" then
        manual(); io.setMain(false); return true
    elseif cmd == "alt_on" then
        manual(); io.setAlternator(true); return true
    elseif cmd == "alt_off" then
        manual(); io.setAlternator(false); return true
    elseif cmd == "gen_on" then
        manual(); io.setGen(true); return true
    elseif cmd == "gen_off" then
        manual(); io.setGen(false); return true
    elseif cmd == "motor_stop" then
        manual()
        local ok, err = io.stopMotor()
        return ok, err
    elseif cmd == "motor_speed" then
        manual()

        local rpm = tonumber(msg.rpm)
        if not rpm then return false, "Invalid RPM" end

        if rpm == 0 then
            return io.stopMotor()
        end

        return io.setMotorSpeed(rpm)
    elseif cmd == "running_topology" then
        manual()

        io.stopMotor()
        io.setGen(false)
        io.setMain(true)
        io.setAlternator(true)

        setState("MANUAL_TOPOLOGY")
        emit("info", "TOPOLOGY_SET", "Running topology applied - physical RUNNING remains telemetry-driven")
        return true
    elseif cmd == "all_cut" then
        manual()

        io.stopMotor()
        io.setMain(false)
        io.setAlternator(false)
        io.setGen(false)
        return true
    end

    return false, "Unknown command: " .. tostring(cmd)
end

local function cleanupSeen()
    local t = protocol.now()

    for id, ts in pairs(seen) do
        if t - ts > SEEN_TTL_MS then
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
