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

local machine = machineInfo.get("collector")
local nodeBus = nodes.new(modem, "collector")
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

runtime.log("collector", "info", "AttaCC SteamPlant application started")

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
    if name == "steamplant.collector" or name == "steam_plant" then return "steamplant" end
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
        recovered and "module initialization recovered" or "collector module loaded")
    emit(id, "success",
        recovered and "MODULE_INIT_RECOVERED" or "MODULE_LOADED",
        recovered and "Module initialization recovered" or "Collector module loaded")
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
        emit("core.collector", "critical", "MODULE_LOAD_ERROR", err)
        return
    end

    if type(mod) ~= "table" then
        local err = tostring(name) .. " did not return a module table"
        moduleLoadError[name] = err
        runtime.set("module:" .. name, "failed", { module = name, detail = err })
        runtime.log("module:" .. name, "error", err)
        emit("core.collector", "critical", "MODULE_LOAD_ERROR", err)
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

for _, name in ipairs((config.collector and config.collector.modules) or {}) do
    loadModule(name)
end

modem.open(config.channels.control)
if config.channels.moduleControl then modem.open(config.channels.moduleControl) end

local function findConfiguredMonitor()
    if not (config.localDisplay and config.localDisplay.enabled) then
        return nil, "display disabled by config"
    end

    local wanted = config.localDisplay.monitorName or "auto"
    return displayCore.find(wanted)
end

local function refreshDisplay()
    local nextMonitor, nextName = findConfiguredMonitor()
    if nextName == monitorName and monitor then return end

    local previousName = monitorName
    if monitor then pcall(display.shutdown, monitor) end
    monitor = nextMonitor
    monitorName = nextName

    if previousName and previousName ~= nextName then
        runtime.log("module:core.display", "info", "monitor detached: " .. tostring(previousName))
        emit("core.collector", "warning", "DISPLAY_DETACHED", "Monitor detached: " .. tostring(previousName))
        print("[display] detached " .. tostring(previousName))
    end

    if monitor then
        local ok, err = pcall(display.init, monitor)
        if ok then
            local status = display.getStatus()
            runtime.set("module:core.display", "active", {
                device = monitorName,
                backend = status and status.backend or "unknown",
            })
            runtime.log("module:core.display", "info", "monitor attached: " .. tostring(monitorName)
                .. " backend=" .. tostring(status and status.backend or "unknown"))
            emit("core.collector", "success", "DISPLAY_ATTACHED",
                "Monitor attached: " .. tostring(monitorName)
                    .. " (" .. tostring(status and status.backend or "unknown") .. ")")
            print("[display] attached " .. tostring(monitorName)
                .. " (" .. tostring(status and status.backend or "unknown") .. ")")
        else
            runtime.set("module:core.display", "failed", { device = monitorName, detail = tostring(err) })
            runtime.log("module:core.display", "error", "display init failed: " .. tostring(err))
            emit("core.collector", "critical", "DISPLAY_ERROR", "Display init failed: " .. tostring(err))
            monitor = nil
        end
    else
        runtime.set("module:core.display", "inactive", { device = nextName, backend = "none" })
    end
end

local function displayModule()
    local configured = config.collector and config.collector.displayModule
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
        local id = canonicalModuleName(config.collector and config.collector.displayModule or "none")
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
    local displayId = canonicalModuleName(config.collector and config.collector.displayModule)
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

local function redrawTerminal()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1,1)

    print(machine.label)
    print("Machine : " .. tostring(machine.key))
    print("Network : " .. tostring(machine.networkLabel) .. " [" .. tostring(machine.network) .. "]")
    print("Preset  : " .. tostring(machine.preset or "infrastructure-node"))
    print("Services: " .. table.concat(machine.services or {}, ", "))
    print("")
    print("Modules:")

    local names = {}
    local seen = {}
    for _, configured in ipairs((config.collector and config.collector.modules) or {}) do
        local id = canonicalModuleName(configured)
        if not seen[id] then
            seen[id] = true
            table.insert(names, id)
        end
    end
    for id in pairs(loaded) do
        if not seen[id] then
            seen[id] = true
            table.insert(names, id)
        end
    end
    table.sort(names)

    if #names == 0 then
        print("  (none configured)")
    else
        for _, id in ipairs(names) do
            local state
            if moduleLoadError[id] then
                state = "FAILED"
            elseif moduleReady[id] == false then
                state = "DEGRADED"
            elseif loaded[id] then
                state = moduleData[id] and "DATA" or "WAIT"
            else
                state = "MISSING"
            end
            print("  " .. id .. " [" .. state .. "]")
            if moduleLoadError[id] then
                print("    " .. tostring(moduleLoadError[id]):sub(1, 44))
            end
        end
    end

    if localEvents[1] then
        print("")
        print("Last: " .. tostring(localEvents[1].code) .. " - " .. tostring(localEvents[1].message))
    end
end

runtime.set("module:attacc.steamplant", "active", {
    detail = "AttaCC SteamPlant application active",
})

local tickSeconds = (config.timing and config.timing.collectorTick) or 0.50
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
                local moduleId = canonicalModuleName(config.collector and config.collector.displayModule)
                if moduleId then
                    router:dispatch(protocol.makeModuleCommand(
                        moduleId, arg, machine.key, nil, {}, machine.key
                    ))
                end
            end

            redrawMonitor()
        end

    elseif event == "peripheral" or event == "peripheral_detach" or event == "monitor_resize" then
        refreshDisplay()
        for id, mod in pairs(loaded) do
            if mod.peripheralChanged then pcall(mod.peripheralChanged, event, p1, ctx) end
            if moduleReady[id] == false then moduleRetryAt[id] = 0 end
        end
        redrawMonitor()

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
        webcap.publish("collector", {
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
