local config = require("lib.config")
local protocol = require("lib.protocol")
local nodes = require("lib.nodes")
local moduleRouter = require("lib.module_router")
local machineInfo = require("lib.machine")
local displayCore = require("lib.display")
local display = require("lib.steamplant_display")
local bus = require("lib.bus")
local network = require("lib.network")
local runtime = require("lib.runtime")
local ioRegistry = require("lib.io_registry")
local webcap = require("lib.webcap")

local modem = protocol.findWirelessModem()
if not modem then error("Wireless modem introuvable") end

local machine = machineInfo.get("steamplant")
local nodeBus = nodes.new(modem, "steamplant")
local net = network.new(config, machine)
local router = moduleRouter.new()

local loaded = {}
local moduleData = {}
local moduleLoadError = {}
local moduleReady = {}
local moduleInitError = {}
local moduleRetryAt = {}
local MODULE_INIT_RETRY_MS = 5000
local localEvents = {}
local MAX_LOCAL_EVENTS = (config.events and config.events.historySize) or 30

local monitor = nil
local monitorName = nil
local monitorPage = "control"
local monitorWidth = nil
local monitorHeight = nil
local displayState = "unknown"

local localPage = "home"
local localHitboxes = {}

runtime.log("steamplant", "info", "AttaCC SteamPlant application started")

local function pushEvent(event)
    table.insert(localEvents, 1, event)
    while #localEvents > MAX_LOCAL_EVENTS do table.remove(localEvents) end
end

local function emit(moduleId, level, code, message, extra)
    local event = {
        type = "module_event",
        network = machine.network,
        module = moduleId,
        machine = machine.key,
        level = level or "info",
        code = code or "EVENT",
        message = message or "",
        timestamp = protocol.now(),
        source = machine.key,
    }

    if type(extra) == "table" then
        for k, v in pairs(extra) do
            if k ~= "type" and k ~= "module" and k ~= "machine" and k ~= "network" then
                event[k] = v
            end
        end
    end

    pushEvent(event)
    protocol.send(modem, config.channels.events, event)
    if config.channels.moduleEvents and config.channels.moduleEvents ~= config.channels.events then
        protocol.send(modem, config.channels.moduleEvents, event)
    end
end

local ctx = {
    config = config,
    protocol = protocol,
    modem = modem,
    machine = machine,
    nodeBus = nodeBus,
    bus = bus,
    network = net,
    io = ioRegistry,
    emit = emit,
}

local function canonicalModuleName(name)
    return name
end

local function initializeModule(id, mod, retry)
    runtime.set("module:" .. id, "starting", {
        module = id,
        detail = retry and "retrying initialization" or "initializing",
    })

    if mod.init then
        local okInit, a, b = pcall(mod.init, ctx)
        if not okInit or a == false then
            local err = tostring(not okInit and a or b)
            moduleReady[id] = false
            moduleInitError[id] = err
            moduleRetryAt[id] = protocol.now() + MODULE_INIT_RETRY_MS
            runtime.set("module:" .. id, "degraded", { module = id, detail = err })
            runtime.log("module:" .. id, "error", "module init failed: " .. err)

            if not retry then
                emit(id, "critical", "MODULE_INIT_ERROR",
                    err .. " - module kept loaded and will retry automatically")
            end
            return false, err
        end
    end

    local recovered = moduleInitError[id] ~= nil
    moduleReady[id] = true
    moduleInitError[id] = nil
    moduleRetryAt[id] = nil
    runtime.set("module:" .. id, "active", { module = id })
    runtime.log("module:" .. id, "info",
        recovered and "module initialization recovered" or "application module loaded")
    emit(id, "success",
        recovered and "MODULE_INIT_RECOVERED" or "MODULE_LOADED",
        recovered and "Module initialization recovered" or "application module loaded")
    return true
end

local function loadModule(name)
    name = canonicalModuleName(name)
    local ok, mod = pcall(require, "modules." .. name)
    if not ok then
        local err = "Unable to load " .. tostring(name) .. ": " .. tostring(mod)
        moduleLoadError[name] = err
        runtime.set("module:" .. name, "failed", { module = name, detail = err })
        runtime.log("module:" .. name, "error", err)
        emit("app.steamplant", "critical", "MODULE_LOAD_ERROR", err)
        return
    end

    if type(mod) ~= "table" then
        local err = tostring(name) .. " did not return a module table"
        moduleLoadError[name] = err
        runtime.set("module:" .. name, "failed", { module = name, detail = err })
        runtime.log("module:" .. name, "error", err)
        emit("app.steamplant", "critical", "MODULE_LOAD_ERROR", err)
        return
    end

    local id = mod.id or name
    moduleLoadError[name] = nil
    moduleLoadError[id] = nil
    loaded[id] = mod

    router:register(id, function(message)
        if not moduleReady[id] then
            emit(id, "warning", "MODULE_NOT_READY",
                "Command ignored while module initialization is degraded")
            return
        end
        if mod.handleCommand then
            local okCall, err = pcall(mod.handleCommand, message, ctx)
            if not okCall then
                emit(id, "critical", "COMMAND_ERROR", tostring(err))
            end
        end
    end)

    initializeModule(id, mod, false)
end

for _, name in ipairs((config.app and config.app.modules) or {}) do
    loadModule(name)
end

modem.open(config.channels.control)
if config.channels.moduleControl then modem.open(config.channels.moduleControl) end

local function findConfiguredMonitor()
    if not (config.localDisplay and config.localDisplay.enabled) then
        return nil, nil, "display disabled by config"
    end

    local wanted = config.localDisplay.monitorName or "auto"
    local found, nameOrErr = displayCore.find(wanted)
    if not found then return nil, nil, nameOrErr end
    return found, nameOrErr, nil
end

local function refreshDisplay(force)
    local nextMonitor, nextName, nextError = findConfiguredMonitor()
    local nextWidth, nextHeight = nil, nil
    if nextMonitor then
        nextWidth, nextHeight = displayCore.geometry(nextMonitor)
    end

    local geometryChanged = nextMonitor and monitorName == nextName
        and monitorWidth ~= nil
        and (monitorWidth ~= nextWidth or monitorHeight ~= nextHeight)

    if monitor and nextName == monitorName and not geometryChanged and not force then
        return
    end

    local previousName = monitorName
    local previousWidth = monitorWidth
    local previousHeight = monitorHeight

    if monitor then pcall(display.shutdown, monitor) end
    monitor = nextMonitor
    monitorName = nextName
    monitorWidth = nextWidth
    monitorHeight = nextHeight

    if previousName and previousName ~= nextName then
        runtime.log("module:core.display", "info", "monitor detached: " .. tostring(previousName))
        emit("app.steamplant", "warning", "DISPLAY_DETACHED",
            "Monitor detached: " .. tostring(previousName))
    end

    if not monitor then
        if displayState ~= "inactive" then
            runtime.log("module:core.display", "warning",
                "display inactive: " .. tostring(nextError or "no monitor detected"))
            emit("app.steamplant", "warning", "DISPLAY_INACTIVE",
                tostring(nextError or "No monitor detected"))
        end
        displayState = "inactive"
        runtime.set("module:core.display", "inactive", {
            backend = "none",
            detail = tostring(nextError or "no monitor detected"),
        })
        return
    end

    local ok, err = pcall(display.init, monitor)
    if not ok then
        displayState = "degraded"
        runtime.set("module:core.display", "degraded", {
            device = monitorName,
            detail = tostring(err),
        })
        runtime.log("module:core.display", "error", "display init failed: " .. tostring(err))
        emit("app.steamplant", "warning", "DISPLAY_ERROR", "Display init failed: " .. tostring(err))
        monitor = nil
        return
    end

    local status = display.getStatus()
    displayState = status and status.error and "degraded" or "active"
    runtime.set("module:core.display", displayState, {
        device = monitorName,
        backend = status and status.backend or "unknown",
        width = monitorWidth,
        height = monitorHeight,
        detail = status and status.error or nil,
    })

    if geometryChanged then
        local before = tostring(previousWidth or "?") .. "x" .. tostring(previousHeight or "?")
        local after = tostring(monitorWidth or "?") .. "x" .. tostring(monitorHeight or "?")
        runtime.log("module:core.display", "info",
            "resolution changed " .. before .. " -> " .. after)
        emit("app.steamplant", "info", "DISPLAY_RESIZED",
            "Display resolution changed " .. before .. " -> " .. after)
    elseif previousName ~= monitorName or displayState ~= "active" then
        runtime.log("module:core.display", "info",
            "monitor active: " .. tostring(monitorName)
                .. " backend=" .. tostring(status and status.backend or "unknown"))
        emit("app.steamplant", "success", "DISPLAY_ACTIVE",
            "Monitor active: " .. tostring(monitorName))
    end
end

local function displayModule()
    local configured = config.app and config.app.displayModule
    if not configured then return nil, nil end
    local id = canonicalModuleName(configured)
    return loaded[id], moduleData[id]
end

local function configuredDisplayTabs()
    local tabs = config.display and config.display.tabs
    if type(tabs) ~= "table" or #tabs == 0 then return { "dashboard" } end
    return tabs
end

local function displayTabEnabled(name)
    for _, tab in ipairs(configuredDisplayTabs()) do
        if tab == name then return true end
    end
    return false
end

local function redrawMonitor()
    refreshDisplay()
    if not monitor then return end

    local status = display.getStatus()
    runtime.set("module:core.display", "active", {
        device = monitorName,
        backend = status and status.backend or "unknown",
    })

    local mod, data = displayModule()
    if not mod then
        local id = canonicalModuleName(config.app and config.app.displayModule or "none")
        monitor.setBackgroundColor(colors.black)
        monitor.setTextColor(colors.orange)
        monitor.clear()
        monitor.setCursorPos(1,1)
        monitor.write("Display module failed: " .. tostring(id))
        local err = moduleLoadError[id]
        if err then
            local _, h = monitor.getSize()
            monitor.setCursorPos(1, math.min(3, h))
            monitor.setTextColor(colors.red)
            monitor.write(tostring(err):sub(1, select(1, monitor.getSize())))
        end
        return
    end

    if display.getBackend() == "ccgraphics" and not displayTabEnabled(monitorPage) then
        monitorPage = configuredDisplayTabs()[1] or "dashboard"
    elseif display.getBackend() == "text" then
        local pages = config.display and config.display.textPages or { "control" }
        local valid = false
        for _, p in ipairs(pages) do if p == monitorPage then valid = true break end end
        if not valid then monitorPage = pages[1] or "control" end
    end

    local debug = mod.getDebug and mod.getDebug(ctx) or {}
    debug.now = protocol.now()
    debug.lastTelemetry = data and data.timestamp or nil
    debug.telemetryAgeMs = data and (protocol.now() - (data.timestamp or protocol.now())) or nil
    debug.display = display.getStatus()
    debug.nodes = nodeBus:list()
    debug.machineLabel = machine.label or machine.hostname or machine.name or machine.key
    local displayId = canonicalModuleName(config.app and config.app.displayModule)
    debug.moduleReady = displayId and moduleReady[displayId] or nil
    debug.moduleInitError = displayId and moduleInitError[displayId] or nil

    display.draw(
        monitor,
        monitorPage,
        data,
        data ~= nil,
        localEvents[1],
        localEvents,
        nil,
        debug
    )
end

local function localButton(x, y, label, key, action)
    term.setCursorPos(x, y)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    write(" " .. label .. " ")
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    table.insert(localHitboxes, {
        x1 = x,
        x2 = x + #label + 1,
        y = y,
        key = key,
        action = action,
    })
end

local function localHeader(title)
    localHitboxes = {}
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(2, 1)
    term.setTextColor(colors.cyan)
    write("ATTACC STEAMPLANT")
    term.setTextColor(colors.gray)
    write("  /  " .. tostring(title))
    term.setCursorPos(2, 3)
    term.setTextColor(colors.white)
    write(tostring(machine.hostname or machine.key))
    term.setTextColor(colors.gray)
    write("  " .. tostring(machine.network))
    term.setTextColor(colors.white)
end

local function moduleState(id)
    if moduleLoadError[id] then return "FAILED", colors.red end
    if moduleReady[id] == false then return "DEGRADED", colors.orange end
    if moduleData[id] then return "ACTIVE", colors.lime end
    if loaded[id] then return "WAIT", colors.yellow end
    return "MISSING", colors.red
end

local function steamData()
    return moduleData["steamplant"]
end

local function drawLocalHome()
    localHeader("HOME")
    local data = steamData()
    local state, stateColor = moduleState("steamplant")

    term.setCursorPos(2, 5)
    term.setTextColor(colors.lightGray)
    write("Network    ")
    term.setTextColor(colors.lime)
    write("ACTIVE")
    term.setTextColor(colors.gray)
    write("  " .. tostring(#nodeBus:list()) .. " node(s)")

    term.setCursorPos(2, 6)
    term.setTextColor(colors.lightGray)
    write("SteamPlant ")
    term.setTextColor(stateColor)
    write(state)
    if data and data.plant then
        term.setTextColor(colors.gray)
        write("  " .. tostring(data.plant.status or "?"))
    end

    term.setCursorPos(2, 7)
    term.setTextColor(colors.lightGray)
    write("Display    ")
    if monitor then
        local status = display.getStatus()
        term.setTextColor(colors.lime)
        write("ACTIVE")
        term.setTextColor(colors.gray)
        local w, h = displayCore.geometry(monitor)
        write("  " .. tostring(monitorName) .. "  "
            .. tostring(w or "?") .. "x" .. tostring(h or "?")
            .. "  " .. tostring(status and status.backend or "?"))
    else
        term.setTextColor(colors.orange)
        write("INACTIVE")
        term.setTextColor(colors.gray)
        write("  no monitor detected")
    end

    if data and data.control then
        term.setCursorPos(2, 9)
        term.setTextColor(colors.lightGray)
        write("Control    ")
        term.setTextColor(data.control.error and colors.red or colors.white)
        write(tostring(data.control.state or "?"))
        term.setTextColor(colors.gray)
        write(data.control.armed and "  AUTO ARMED" or "  AUTO DISARMED")
    end

    term.setCursorPos(2, 11)
    term.setTextColor(colors.yellow)
    write("TOOLS")
    localButton(2, 13, "Modules", keys.m, "modules")
    localButton(14, 13, "Data", keys.d, "data")
    localButton(22, 13, "Events", keys.e, "events")
    localButton(32, 13, "Display", keys.p, "display")
    localButton(44, 13, "Refresh", keys.r, "refresh")

    term.setCursorPos(2, 15)
    term.setTextColor(colors.yellow)
    write("RECENT")
    local y = 16
    for i = 1, math.min(4, #localEvents) do
        local event = localEvents[i]
        term.setCursorPos(2, y)
        term.setTextColor(event.level == "critical" and colors.red
            or event.level == "warning" and colors.orange
            or event.level == "success" and colors.lime
            or colors.lightGray)
        write(tostring(event.code or "EVENT") .. "  "
            .. tostring(event.message or ""):sub(1, 48))
        y = y + 1
    end
    term.setTextColor(colors.white)
end

local function drawLocalModules()
    localHeader("MODULES")
    local _, h = term.getSize()
    local names = {}
    for id in pairs(loaded) do table.insert(names, id) end
    for id in pairs(moduleLoadError) do
        local found = false
        for _, name in ipairs(names) do if name == id then found = true break end end
        if not found then table.insert(names, id) end
    end
    table.sort(names)

    local y = 5
    for _, id in ipairs(names) do
        if y >= h - 1 then break end
        local state, color = moduleState(id)
        term.setCursorPos(2, y)
        term.setTextColor(colors.white)
        write(string.format("%-18s ", tostring(id)))
        term.setTextColor(color)
        write(state)
        if moduleInitError[id] then
            term.setTextColor(colors.gray)
            write("  " .. tostring(moduleInitError[id]):sub(1, 35))
        end
        y = y + 1
    end

    if #names == 0 then
        term.setCursorPos(2, y)
        term.setTextColor(colors.gray)
        write("(no modules)")
    end

    localButton(2, h, "Back", keys.b, "home")
    localButton(12, h, "Refresh", keys.r, "refresh")
end

local function drawLocalData()
    localHeader("DATA")
    local data = steamData()
    local _, h = term.getSize()

    if not data then
        term.setCursorPos(2, 5)
        term.setTextColor(colors.orange)
        write("Waiting for SteamPlant telemetry...")
    else
        local lines = {
            string.format("Plant     %s", tostring(data.plant and data.plant.status or "?")),
            string.format("RPM       %.1f", tonumber(data.power and data.power.rpm) or 0),
            string.format("Load      %.1f%%", tonumber(data.power and data.power.load) or 0),
            string.format("Stress    %.0f / %.0f",
                tonumber(data.power and data.power.stress) or 0,
                tonumber(data.power and data.power.capacity) or 0),
            string.format("Motor     %.1f rpm  %.0f FE/t",
                tonumber(data.motor and data.motor.rpm) or 0,
                tonumber(data.motor and data.motor.consumption) or 0),
            string.format("Boiler    water %.0f%%  heat %.0f%%",
                tonumber(data.boiler and data.boiler.water) or 0,
                tonumber(data.boiler and data.boiler.heat) or 0),
            string.format("Battery   %.1f%%",
                tonumber(data.battery and data.battery.percent) or 0),
            string.format("Control   %s",
                tostring(data.control and data.control.state or "?")),
        }

        for i, line in ipairs(lines) do
            term.setCursorPos(2, 4 + i)
            term.setTextColor(i == 1 and colors.yellow or colors.white)
            write(line)
        end
    end

    localButton(2, h, "Back", keys.b, "home")
    localButton(12, h, "Refresh", keys.r, "refresh")
end

local function drawLocalEvents()
    localHeader("EVENTS")
    local _, h = term.getSize()
    local y = 5

    if #localEvents == 0 then
        term.setCursorPos(2, y)
        term.setTextColor(colors.gray)
        write("(no events)")
    else
        for i = 1, math.min(#localEvents, h - 6) do
            local event = localEvents[i]
            term.setCursorPos(2, y)
            term.setTextColor(event.level == "critical" and colors.red
                or event.level == "warning" and colors.orange
                or event.level == "success" and colors.lime
                or colors.lightGray)
            write(tostring(event.code or "EVENT") .. "  "
                .. tostring(event.message or ""):sub(1, 48))
            y = y + 1
        end
    end

    localButton(2, h, "Back", keys.b, "home")
    localButton(12, h, "Refresh", keys.r, "refresh")
end

local function drawLocalDisplay()
    localHeader("DISPLAY")
    local _, h = term.getSize()
    term.setCursorPos(2, 5)

    if monitor then
        local status = display.getStatus()
        local w, mh = displayCore.geometry(monitor)
        term.setTextColor(colors.lime)
        print("State      : ACTIVE")
        term.setTextColor(colors.white)
        print("Peripheral : " .. tostring(monitorName))
        print("Resolution : " .. tostring(w or "?") .. "x" .. tostring(mh or "?"))
        print("Backend    : " .. tostring(status and status.backend or "?"))
        print("Page       : " .. tostring(monitorPage))
    else
        term.setTextColor(colors.orange)
        print("State      : INACTIVE")
        term.setTextColor(colors.gray)
        print("Reason     : no monitor detected")
        print("")
        print("SteamPlant control continues without a display.")
    end

    localButton(2, h, "Back", keys.b, "home")
    localButton(12, h, "Refresh", keys.r, "refresh")
end

local function redrawTerminal()
    if localPage == "modules" then
        drawLocalModules()
    elseif localPage == "data" then
        drawLocalData()
    elseif localPage == "events" then
        drawLocalEvents()
    elseif localPage == "display" then
        drawLocalDisplay()
    else
        drawLocalHome()
    end
end

local function localAction(action)
    if action == "home" or action == "modules" or action == "data"
        or action == "events" or action == "display"
    then
        localPage = action
    elseif action == "refresh" then
        nodeBus:tick()
        refreshDisplay()
    end
end

local function localKey(key)
    for _, box in ipairs(localHitboxes) do
        if box.key == key then
            localAction(box.action)
            return
        end
    end
end

local function localMouse(x, y)
    for _, box in ipairs(localHitboxes) do
        if y == box.y and x >= box.x1 and x <= box.x2 then
            localAction(box.action)
            return
        end
    end
end

runtime.set("app:steamplant", "active", {
    detail = "AttaCC SteamPlant application active",
})

local tickSeconds = (config.timing and config.timing.appTickSeconds) or 0.50
local timer = os.startTimer(tickSeconds)
redrawTerminal()
redrawMonitor()

while true do
    local event, p1, p2, p3, p4 = os.pullEvent()

    if event == bus.EVENT then
        bus.handle(event, p1, p2, p3)

    elseif event == "modem_message" then
        if net then net:handle(p2, p3, p4) end
        local nodeAction = nodeBus:handle(p2, p4)
        if nodeAction == "reboot" then
            sleep(0.15)
            os.reboot()
        end

        if p2 == config.channels.control or p2 == config.channels.moduleControl then
            router:dispatch(p4)
        end

    elseif event == "monitor_touch" then
        refreshDisplay()
        if monitor and (not monitorName or p1 == monitorName) then
            local action, arg = display.actionAt(p2, p3)

            if action == "page" then
                if display.getBackend() == "ccgraphics" then
                    if displayTabEnabled(arg) then monitorPage = arg end
                else
                    monitorPage = arg
                end
            elseif action == "backend" and arg then
                local ok = display.setBackend(monitor, arg)
                if ok then monitorPage = arg == "ccgraphics" and "graphs" or "control" end
            elseif action == "command" and arg then
                local moduleId = canonicalModuleName(config.app and config.app.displayModule)
                if moduleId then
                    router:dispatch(protocol.makeModuleCommand(
                        moduleId, arg, machine.key, nil, {}, machine.key
                    ))
                end
            end

            redrawMonitor()
        end

    elseif event == "mouse_click" then
        localMouse(p2, p3)
        redrawTerminal()

    elseif event == "key" then
        localKey(p1)
        redrawTerminal()

    elseif event == "peripheral" or event == "peripheral_detach" then
        refreshDisplay(true)
        for id, mod in pairs(loaded) do
            if mod.peripheralChanged then pcall(mod.peripheralChanged, event, p1, ctx) end
            if moduleReady[id] == false then moduleRetryAt[id] = 0 end
        end
        redrawMonitor()
        redrawTerminal()

    elseif event == "monitor_resize" then
        refreshDisplay(true)
        redrawMonitor()
        redrawTerminal()

    elseif event == "timer" and p1 == timer then
        nodeBus:tick()

        for id, mod in pairs(loaded) do
            if moduleReady[id] == false
                and protocol.now() >= (moduleRetryAt[id] or 0)
            then
                initializeModule(id, mod, true)
            end

            if moduleReady[id] and mod.update then
                local ok, err = pcall(mod.update, ctx)
                if not ok then
                    runtime.set("module:" .. id, "degraded", { module = id, detail = tostring(err) })
                    runtime.log("module:" .. id, "error", "update failed: " .. tostring(err))
                    emit(id, "critical", "MODULE_UPDATE_ERROR", tostring(err))
                end
            end

            if moduleReady[id] and mod.collect then
                local ok, data = pcall(mod.collect, ctx)
                if ok and type(data) == "table" then
                    data.type = data.type or "module_telemetry"
                    data.network = machine.network
                    data.module = data.module or id
                    data.machine = machine.key
                    data.timestamp = data.timestamp or protocol.now()
                    moduleData[id] = data
                    runtime.set("module:" .. id, "active", { module = id, detail = "telemetry live" })

                    protocol.send(modem, config.channels.telemetry, data)
                    if config.channels.moduleData and config.channels.moduleData ~= config.channels.telemetry then
                        protocol.send(modem, config.channels.moduleData, data)
                    end
                elseif not ok then
                    runtime.set("module:" .. id, "degraded", { module = id, detail = tostring(data) })
                    runtime.log("module:" .. id, "error", "collect failed: " .. tostring(data))
                    emit(id, "critical", "COLLECT_ERROR", tostring(data))
                end
            end
        end

        local moduleStates = {}
        for id in pairs(loaded) do
            moduleStates[id] = moduleReady[id] == false and "degraded"
                or (moduleData[id] and "active" or "loaded")
        end
        webcap.publish("steamplant", {
            monitor = monitorName,
            displayPage = monitorPage,
            modules = moduleStates,
            lastEvent = localEvents[1] and {
                level = localEvents[1].level,
                code = localEvents[1].code,
                message = localEvents[1].message,
            } or nil,
        })

        redrawTerminal()
        redrawMonitor()
        timer = os.startTimer(tickSeconds)
    end
end
