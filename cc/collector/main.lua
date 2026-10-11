local config = require("lib.config")
local protocol = require("lib.protocol")
local telemetry = require("lib.telemetry")
local controller = require("lib.controller")
local nodes = require("lib.nodes")
local moduleRouter = require("lib.module_router")
local machineInfo = require("lib.machine")
local display = require("lib.display")

local modem = protocol.findWirelessModem()
if not modem then error("Wireless modem introuvable") end

local localMachine = machineInfo.get("collector")
local nodeBus = nodes.new(modem, "collector")
local modules = moduleRouter.new()

local monitor = nil
local monitorName = nil
local monitorPage = "dashboard"
local localMonitorStatus = nil

local function findConfiguredMonitor()
    if not (config.localDisplay and config.localDisplay.enabled) then
        return nil, nil
    end

    local wanted = config.localDisplay.monitorName
    if wanted and wanted ~= "" then
        if peripheral.isPresent(wanted) and peripheral.getType(wanted) == "monitor" then
            return peripheral.wrap(wanted), wanted
        end
        return nil, wanted
    end

    local found = peripheral.find("monitor")
    return found, found and peripheral.getName(found) or nil
end

local function refreshDisplay()
    local nextMonitor, nextName = findConfiguredMonitor()

    if nextName ~= monitorName then
        if monitor then pcall(display.shutdown, monitor) end
        monitor = nextMonitor
        monitorName = nextName
        localMonitorStatus = nil

        if monitor then
            local ok, status = pcall(display.init, monitor)
            if ok then
                localMonitorStatus = status
            else
                monitor = nil
                localMonitorStatus = { backend = "none", degraded = true, error = tostring(status) }
            end
        end
    elseif not monitor and nextMonitor then
        monitor = nextMonitor
        local ok, status = pcall(display.init, monitor)
        localMonitorStatus = ok and status or { backend = "none", degraded = true, error = tostring(status) }
        if not ok then monitor = nil end
    end
end
modules:register("steamplant", function(message)
    controller.handleCommand(modem, message)
end)

modem.open(config.channels.control)

local page = "status"
local heartbeat = false
local tickCount = 0
local lastData = nil
local lastCollectError = nil
local localEvents = {}
local MAX_LOCAL_EVENTS = 24

local function pushLocalEvent(event)
    table.insert(localEvents, 1, event)
    while #localEvents > MAX_LOCAL_EVENTS do
        table.remove(localEvents)
    end
end

controller.setEventSink(function(event)
    event.type = event.type or "module_event"
    event.module = event.module or "steamplant"
    event.machine = event.machine or localMachine.key
    pushLocalEvent(event)
    protocol.send(modem, config.channels.events, event)
end)

-- CC redstone outputs default low on reboot, which would engage a Create
-- clutch. Cut the GEN startup branch immediately before waiting for telemetry.
controller.prepareBootOutputs()

local function fmtTime(ms)
    if not ms then return "--:--:--" end
    local sec = math.floor(ms / 1000)
    local h = math.floor((sec / 3600) % 24)
    local m = math.floor((sec / 60) % 60)
    local s = sec % 60
    return string.format("%02d:%02d:%02d", h, m, s)
end

local function fmtMs(ms)
    if ms == nil then return "-" end
    if ms < 0 then return "due" end
    if math.abs(ms) < 1000 then return tostring(math.floor(ms)) .. "ms" end
    return string.format("%.1fs", ms / 1000)
end

local function writeAt(x, y, text, color)
    local w, h = term.getSize()
    if y < 1 or y > h then return end
    text = tostring(text or "")
    if #text > w - x + 1 then
        text = text:sub(1, math.max(0, w - x + 1))
    end
    term.setCursorPos(x, y)
    if color then term.setTextColor(color) end
    term.write(text)
    term.setTextColor(colors.white)
end

local function header(title)
    local w = select(1, term.getSize())
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()

    writeAt(1, 1, "STEAM PLANT COLLECTOR", colors.yellow)
    local blink = heartbeat and "[*]" or "[ ]"
    writeAt(math.max(1, w - #blink + 1), 1, blink, heartbeat and colors.lime or colors.gray)
    writeAt(1, 2, title, colors.lightBlue)
end

local function displayStatus(data)
    header("STATUS  [D] DEBUG")

    if not data then
        writeAt(1, 4, "Waiting for telemetry...", colors.orange)
        if lastCollectError then
            writeAt(1, 6, "Last error:", colors.red)
            writeAt(1, 7, lastCollectError, colors.red)
        end
        return
    end

    writeAt(1, 4, "Plant: " .. tostring(data.plant.status))
    writeAt(1, 5, "Ctrl : " .. tostring(data.control.state))
    writeAt(1, 6, "Armed: " .. tostring(data.control.armed))
    writeAt(1, 7, "Offline: " .. tostring(data.control.plantOffline))

    writeAt(1, 9, string.format("RPM: %.1f  Load: %.1f%%", data.power.rpm, data.power.load))
    writeAt(1, 10, string.format("Stress: %.0f / %.0f SU", data.power.stress, data.power.capacity))
    writeAt(1, 12, string.format("Boiler L%d  Water %.1f%% Heat %.1f%%",
        data.boiler.level, data.boiler.water, data.boiler.heat))
    writeAt(1, 14, string.format("Battery %.1f%%  Motor %.1f RPM",
        data.battery.percent, data.motor.rpm))

    writeAt(1, 16,
        "MAIN " .. (data.control.mainClutchEngaged and "ON" or "CUT")
        .. " | GEN " .. (data.control.genClutchEngaged and "ON" or "CUT")
        .. " | ALT " .. (data.control.alternatorClutchEngaged and "ON" or "CUT"),
        data.control.alternatorClutchEngaged and colors.lime or colors.orange)

    if data.control.error then
        writeAt(1, 18, "ERR: " .. tostring(data.control.error), colors.red)
    else
        writeAt(1, 18, "Loop tick: " .. tostring(tickCount), colors.gray)
    end
end

local function displayDebug()
    header("DEBUG  [S] STATUS")

    local d = controller.getDebug()
    local _, h = term.getSize()

    writeAt(1, 4, "Now      : " .. fmtTime(d.now))
    writeAt(1, 5, "State    : " .. tostring(d.state) .. " (" .. fmtMs(d.stateAgeMs) .. ")")
    writeAt(1, 6, "Init     : " .. tostring(d.initialized) .. "  Reason: " .. tostring(d.stateReason or "-"))
    writeAt(1, 7, "Armed    : " .. tostring(d.armed) .. "  Offline: " .. tostring(d.plantOffline))
    writeAt(1, 8, "Origin   : " .. tostring(d.procedureOrigin or "-"))
    writeAt(1, 9, "Auto in  : " .. fmtMs(d.autoStartInMs) .. "  Attempts: " .. tostring(d.autoAttempts))
    writeAt(1, 10, "Deadline : " .. fmtMs(d.deadlineInMs) .. "  Verify: " .. fmtMs(d.verifyInMs))
    writeAt(1, 11, "ALT latch: " .. fmtMs(d.alternatorLatchInMs))
    writeAt(1, 12,
        "Outputs  : M=" .. (d.mainCommanded and "ON" or "CUT")
        .. " G=" .. (d.genCommanded and "ON" or "CUT")
        .. " A=" .. (d.alternatorCommanded and "ON" or "CUT"))

    if lastCollectError then
        writeAt(1, 13, "Collect: " .. lastCollectError, colors.red)
    else
        writeAt(1, 13, "Collect: OK", colors.lime)
    end

    writeAt(1, 15, "EVENTS (newest first)", colors.yellow)

    local row = 16
    for i = 1, #localEvents do
        if row > h then break end
        local e = localEvents[i]
        local levelColor =
            e.level == "critical" and colors.red
            or e.level == "warning" and colors.orange
            or e.level == "success" and colors.lime
            or colors.lightBlue

        local line = fmtTime(e.timestamp)
            .. " " .. tostring(e.code or "EVENT")
            .. " " .. tostring(e.message or "")

        writeAt(1, row, line, levelColor)
        row = row + 1
    end
end

local function redrawLocalMonitor()
    refreshDisplay()
    if not monitor then return end

    local debug = controller.getDebug()
    debug.now = protocol.now()
    debug.lastTelemetry = lastData and lastData.timestamp or nil
    debug.telemetryAgeMs = lastData and (protocol.now() - (lastData.timestamp or protocol.now())) or nil
    debug.display = display.getStatus()
    debug.nodes = nodeBus:list()

    display.draw(
        monitor,
        monitorPage,
        lastData,
        lastData ~= nil,
        localEvents[1],
        localEvents,
        nil,
        debug
    )
end

local function redraw()
    if page == "debug" then
        displayDebug()
    else
        displayStatus(lastData)
    end
    redrawLocalMonitor()
end

local tickTimer = os.startTimer(config.timing.collectorTick)
redraw()

while true do
    local event, p1, p2, p3, p4 = os.pullEvent()

    if event == "modem_message" then
        local nodeAction = nodeBus:handle(p2, p4)
        if nodeAction == "reboot" then
            sleep(0.15)
            os.reboot()
        end

        if p2 == config.channels.control then
            modules:dispatch(p4)
        end

    elseif event == "monitor_touch" then
        refreshDisplay()
        if monitor and (not monitorName or p1 == monitorName) then
            local action, arg = display.actionAt(p2, p3)

            if action == "page" then
                monitorPage = arg
            elseif action == "command" and arg then
                modules:dispatch(protocol.makeModuleCommand(
                    "steamplant",
                    arg,
                    localMachine.key,
                    nil,
                    {}
                ))
            end

            redrawLocalMonitor()
        end

    elseif event == "peripheral" or event == "peripheral_detach" then
        refreshDisplay()
        redrawLocalMonitor()

    elseif event == "char" then
        local key = tostring(p1):lower()
        if key == "d" then
            page = "debug"
            redraw()
        elseif key == "s" then
            page = "status"
            redraw()
        end

    elseif event == "key" then
        if p1 == keys.tab then
            page = page == "status" and "debug" or "status"
            redraw()
        end

    elseif event == "timer" and p1 == tickTimer then
        tickCount = tickCount + 1
        heartbeat = not heartbeat

        -- Read every Create peripheral only ONCE per tick.
        local ok, data = pcall(telemetry.collect, controller)

        if ok then
            lastCollectError = nil

            -- Synchronize the controller once from the real physical state.
            -- This is observational only: no clutch/motor output is forced at boot.
            if not controller.isInitialized() then
                controller.initialize(data.power)
            end

            controller.updateDetection(data.power)
            controller.update()

            data.control.state = controller.getState()
            data.control.error = controller.getError()
            data.control.automatic = controller.isAutomatic()
            data.control.armed = controller.isArmed()
            data.control.plantOffline = controller.isPlantOffline()

            lastData = data
            protocol.send(modem, config.channels.telemetry, data)
        else
            lastCollectError = tostring(data)
            pushLocalEvent({
                type = "plant_event",
                level = "critical",
                code = "COLLECT_ERROR",
                message = lastCollectError,
                timestamp = protocol.now(),
                source = "collector",
            })
        end

        nodeBus:tick()
        redraw()
        tickTimer = os.startTimer(config.timing.collectorTick)
    end
end
