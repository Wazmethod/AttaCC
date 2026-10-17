-- Native controller: receives AttaCC app and I/O service, not internal libs.
local M={}
function M.setup(app,io)
    assert(type(app)=="table" and type(io)=="table","SDK app and output service required")
    local function now() return os.epoch("utc") end
    local config=setmetatable({}, {__index=function(_,section)
        return setmetatable({}, {__index=function(_,key)
            return app:config(section.."."..key)
        end})
    end})
    local nativeOutputs=io
    io=setmetatable({}, {__index=function(_,key)
        local fn=nativeOutputs[key]
        if type(fn)~="function" then return fn end
        if key=="setMain" or key=="setAlternator" or key=="setGen" then
            return function(...)
                local ok,err=fn(...)
                if not ok then error("hardware "..key..": "..tostring(err),2) end
                return true
            end
        end
        return fn
    end})
    local C={}


-- Controller states are centralized here instead of being scattered as
-- anonymous string literals throughout the state machine.
local STATES = {
    BOOT = "BOOT",
    RUNNING = "RUNNING",
    OFFLINE = "OFFLINE",
    DEGRADED = "DEGRADED",
    AUTO_WAIT_RPM = "AUTO_WAIT_RPM",
    AUTO_TRANSFER = "AUTO_TRANSFER",
    AUTO_VERIFY = "AUTO_VERIFY",
    AUTO_RETRY_WAIT = "AUTO_RETRY_WAIT",
    ERROR = "ERROR",
}

C.STATES = STATES

local state = STATES.BOOT
local stateSince = now()
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
            timestamp = now(),
            source = "steamplant",
        })
    end
end

function C.setEventSink(fn)
    eventSink = fn
end

local function savePersistentState()
    return app:state("controller",{armed=armed})
end

local function loadPersistentState()
    local data=app:state("controller")
    if type(data)=="table" and type(data.armed)=="boolean" then
        armed=data.armed
    end
end

loadPersistentState()

local function transition(newState, reason, err)
    local oldState = state

    state = newState
    stateSince = now()
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

function C.getState() return state end
function C.getError() return lastError end
function C.isArmed() return armed end
function C.isPlantOffline() return plantOffline end
function C.isInitialized() return initialized end

local function procedureActive()
    return state == STATES.AUTO_WAIT_RPM
        or state == STATES.AUTO_TRANSFER
        or state == STATES.AUTO_VERIFY
end

function C.isAutomatic()
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
    local stopped,stopErr=io.stopMotor()
    local cut,cutErr=io.setGen(false)
    if not stopped or not cut then
        local reason=not stopped and ("motor: "..tostring(stopErr))
            or ("generator clutch: "..tostring(cutErr))
        emit("critical","STARTUP_STOP_INCOMPLETE",reason)
        return false,reason
    end
    return true
end

-- Restore the last commanded topology before telemetry starts. On first boot,
-- or when the persisted file is missing/invalid, io.restoreOutputs() falls back
-- to config.bootState.
function C.prepareBootOutputs()
    local ok, err, source = io.restoreOutputs()

    if not ok then
        emit("critical", "BOOT_OUTPUT_ERROR", "Unable to restore outputs: " .. tostring(err))
        return false, err
    end

    local outputs = io.getOutputState()
    emit(
        "info",
        source == "persisted" and "BOOT_OUTPUT_RESTORE" or "BOOT_OUTPUT_FALLBACK",
        "Outputs restored from " .. tostring(source)
            .. ": MAIN=" .. (outputs.main and "ON" or "CUT")
            .. " GEN=" .. (outputs.gen and "ON" or "CUT")
            .. " ALT=" .. (outputs.alternator and "ON" or "CUT")
            .. " MOTOR=" .. tostring(outputs.motorRPM)
    )

    return true
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

    local ok,err=io.setMain(topology.main)
    if not ok then return false,"main clutch: "..tostring(err) end
    ok,err=io.setGen(topology.gen)
    if not ok then return false,"generator clutch: "..tostring(err) end
    ok,err=io.setAlternator(topology.alternator)
    if not ok then return false,"alternator clutch: "..tostring(err) end

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
    local ok,err=io.setAlternator(true)
    if not ok then return false,err end
    alternatorLatchUntil = now() + (ms or 3000)
    if announce then
        emit("info", "ALT_LATCH_START", "Alternator clutch asserted for startup transfer")
    end
    return true
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
function C.initialize(power)
    if initialized then return state end

    local detected = classifyPhysical(power)
    initialized = true

    plantOffline = detected == STATES.OFFLINE
    offlineSince = plantOffline and now() or nil
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
        autoStartAt = now() + config.procedure.autoRestartDelayMs
        emit("warning", "AUTO_RESTART_PENDING", "Plant offline at boot - automatic black-start scheduled")
    end

    return state
end

function C.getDebug()
    local now = now()

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
        outputs = io.getOutputState(),
    }
end

local function scheduleRetry(reason)
    local stopped,stopErr=stopBlackStartDrive()
    clearProcedureTimers()
    if not stopped then
        autoStartAt=nil
        local failure=tostring(reason).."; unable to stop startup drive: "..tostring(stopErr)
        transition(STATES.ERROR,failure,failure)
        emit("critical","START_ERROR",failure)
        return
    end

    if procedureOrigin == "automatic"
        and armed
        and plantOffline
        and autoAttempts < config.procedure.maxAutoAttempts
    then
        autoStartAt = now() + config.procedure.retryDelayMs
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

function C.setArmed(value)
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
        and not C.isAutomatic()
        and state ~= STATES.ERROR
    then
        autoStartAt = now() + config.procedure.autoRestartDelayMs
        emit("warning", "AUTO_RESTART_PENDING", "Plant offline - automatic black-start scheduled")
    end

    return true
end

function C.startProcedure(origin)
    if not initialized then
        return false, "Controller not initialized"
    end
    -- A duplicate request must not reset deadlines or restart a live sequence.
    if procedureActive() then
        return false, "Startup procedure already in progress"
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

    deadline = now() + config.procedure.timeoutMs
    rpmStableSince = nil
    verifyDeadline = nil

    transition(STATES.AUTO_WAIT_RPM, "waiting for startup RPM")
    return true
end

function C.abortProcedure()
    local stopped,stopErr=io.stopMotor()
    local cut,cutErr=io.setGen(false)
    clearProcedureTimers()
    clearAlternatorLatch()
    autoStartAt = nil
    procedureOrigin = nil

    transition(classifyPhysical({
        rpm = io.getSpeed() or 0,
        capacity = io.call("stressometer", "getStressCapacity", 0) or 0,
    }), "startup procedure aborted")

    if not stopped or not cut then
        local reason=not stopped and ("motor: "..tostring(stopErr))
            or ("generator clutch: "..tostring(cutErr))
        emit("critical","AUTO_ABORT_INCOMPLETE",reason)
        return false,reason
    end
    emit("warning", "AUTO_ABORTED", "Startup procedure aborted")
    return true
end

local function stepWaitRpm()
    if deadline and now() > deadline then
        scheduleRetry("Timeout waiting for startup RPM")
        return
    end

    local rpm = math.abs(io.getSpeed() or 0)

    if rpm < config.procedure.minRPM then
        rpmStableSince = nil
        return
    end

    if not rpmStableSince then
        rpmStableSince = now()
        return
    end

    if now() - rpmStableSince < config.procedure.stableMs then
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
    if now() - stateSince < config.procedure.transferDelayMs then
        return
    end

    local ok, err = applyTopology("RUNNING")
    if not ok then
        scheduleRetry("Running topology failed: " .. tostring(err))
        return
    end

    local latched,latchErr=latchAlternator(5000, true)
    if not latched then scheduleRetry("Alternator latch failed: "..tostring(latchErr));return end
    verifyDeadline = now() + config.procedure.verifyRunningMs

    transition(STATES.AUTO_VERIFY, "final topology applied")
    emit("info", "AUTO_VERIFY", "Transfer complete - alternator engaged, verifying physical plant rotation")
end

local function stepVerify()
    -- Keep the final topology asserted while the kinetic network settles.
    -- Any failed write must cancel verification rather than hide the failure.
    local ok,err=io.setMain(true)
    if not ok then scheduleRetry("Verification main clutch failed: "..tostring(err));return end
    ok,err=io.setGen(false)
    if not ok then scheduleRetry("Verification generator clutch failed: "..tostring(err));return end
    ok,err=io.setAlternator(true)
    if not ok then scheduleRetry("Verification alternator clutch failed: "..tostring(err));return end
    alternatorLatchUntil=now()+5000
    ok,err=io.stopMotor()
    if not ok then scheduleRetry("Verification motor stop failed: "..tostring(err));return end

    if verifyDeadline and now() > verifyDeadline then
        scheduleRetry("Transfer completed but plant never reached RUNNING telemetry")
    end
end

local PROCEDURE_STEPS = {
    [STATES.AUTO_WAIT_RPM] = stepWaitRpm,
    [STATES.AUTO_TRANSFER] = stepTransfer,
    [STATES.AUTO_VERIFY] = stepVerify,
}

function C.update()
    if not initialized then return end

    if alternatorLatchUntil then
        if now() < alternatorLatchUntil then
            io.setAlternator(true)
        else
            alternatorLatchUntil = nil
        end
    end

    if autoStartAt
        and armed
        and plantOffline
        and now() >= autoStartAt
        and not procedureActive()
    then
        autoStartAt = nil
        C.startProcedure("automatic")
        return
    end

    local step = PROCEDURE_STEPS[state]
    if step then step() end
end

function C.updateDetection(power)
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

        local latched,latchErr=latchAlternator(5000, false)
        if not latched then scheduleRetry("Final alternator latch failed: "..tostring(latchErr));return end
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
            offlineSince = now()
        end

        if not plantOffline
            and now() - offlineSince >= config.detection.offlineConfirmMs
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

            if armed and not C.isAutomatic() then
                autoStartAt = now() + config.procedure.autoRestartDelayMs
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
            recoverySince = now()
            return
        end

        if now() - recoverySince >= config.detection.recoveryConfirmMs then
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

local function operatorOverride(reason)
    local wasAutomatic=procedureActive() or state == STATES.AUTO_RETRY_WAIT
    clearProcedureTimers()
    clearAlternatorLatch()
    autoStartAt = nil
    procedureOrigin = nil

    if wasAutomatic then
        -- Clearing timers alone leaves the state machine in an AUTO_* state;
        -- the next update would otherwise resume an already cancelled sequence.
        transition(classifyPhysical({
            rpm=io.getSpeed() or 0,
            capacity=io.call("stressometer","getStressCapacity",0) or 0,
        }), "manual operator override")
        emit("warning", "STARTUP_CANCELLED", "Startup sequence cancelled by operator: " .. tostring(reason))
    end
end

local function emitOperatorAction(message)
    emit("info", "OPERATOR_ACTION", message)
end

local function execute(msg)
    local cmd = msg.command

    if cmd == "procedure" then
        return C.startProcedure("manual")

    elseif cmd == "abort" then
        return C.abortProcedure()

    elseif cmd == "arm" then
        return C.setArmed(true)

    elseif cmd == "disarm" then
        return C.setArmed(false)

    elseif cmd == "main_on" then
        operatorOverride("MAIN ENGAGE")
        local ok,err=io.setMain(true)
        if not ok then return false,err end
        emitOperatorAction("MAIN clutch engaged")
        return true

    elseif cmd == "main_off" then
        operatorOverride("MAIN CUT")
        local ok,err=io.setMain(false)
        if not ok then return false,err end
        emitOperatorAction("MAIN clutch cut")
        return true

    elseif cmd == "alt_on" then
        operatorOverride("ALT ENGAGE")
        local ok,err=io.setAlternator(true)
        if not ok then return false,err end
        emitOperatorAction("ALT clutch engaged")
        return true

    elseif cmd == "alt_off" then
        operatorOverride("ALT CUT")
        local ok,err=io.setAlternator(false)
        if not ok then return false,err end
        emitOperatorAction("ALT clutch cut")
        return true

    elseif cmd == "gen_on" then
        operatorOverride("GEN ENGAGE")
        local ok,err=io.setGen(true)
        if not ok then return false,err end
        emitOperatorAction("GEN clutch engaged")
        return true

    elseif cmd == "gen_off" then
        operatorOverride("GEN CUT")
        local ok,err=io.setGen(false)
        if not ok then return false,err end
        emitOperatorAction("GEN clutch cut")
        return true

    elseif cmd == "motor_32" or cmd == "motor_64" or cmd == "motor_128" then
        operatorOverride("MOTOR SPEED")
        local rpm = tonumber(cmd:match("motor_(%d+)"))
        local ok, err = io.setMotorSpeed(rpm)
        if ok then emitOperatorAction("Electric motor set to " .. tostring(rpm) .. " RPM") end
        return ok, err

    elseif cmd == "motor_stop" then
        operatorOverride("MOTOR STOP")
        local ok, err = io.stopMotor()
        if ok then emitOperatorAction("Electric motor stopped") end
        return ok, err

    elseif cmd == "motor_speed" then
        operatorOverride("MOTOR SPEED")

        local rpm = tonumber(msg.rpm)
        if not rpm then return false, "Invalid RPM" end

        local ok, err
        if rpm == 0 then
            ok, err = io.stopMotor()
        else
            ok, err = io.setMotorSpeed(rpm)
        end

        if ok then emitOperatorAction("Electric motor set to " .. tostring(rpm) .. " RPM") end
        return ok, err

    elseif cmd == "running_topology" then
        if not initialized then return false,"controller not initialized" end
        -- This engages the running transmission and must not start a stopped plant.
        local rpm=math.abs(io.getSpeed() or 0)
        local capacity=io.call("stressometer","getStressCapacity",0) or 0
        if rpm<config.detection.onlineRpm
            or capacity<config.detection.onlineCapacity then
            return false,"running topology requires online RPM and capacity"
        end
        operatorOverride("RUNNING TOPOLOGY")

        local ok, err = applyTopology("RUNNING")
        if not ok then return false, err end

        emit("info", "TOPOLOGY_SET", "Running topology applied by operator")
        return true

    elseif cmd == "all_cut" then
        operatorOverride("ALL CUT")
        local ok, err = applyTopology("ALL_CUT")
        if ok then emit("warning", "TOPOLOGY_SET", "All clutches cut by operator") end
        return ok, err
    end

    return false, "Unknown command: " .. tostring(cmd)
end

-- Local SDK commands use the same interlocks and transitions as network commands.
function C.executeCommand(command, args)
    if type(command) ~= "string" then return false, "invalid command" end
    args = type(args) == "table" and args or {}
    return execute({command=command, rpm=args.rpm})
end

-- SDK transport owns network authentication, deduplication and ACK.
return C
end
return M
