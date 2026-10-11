local config = require("lib.config")
local protocol = require("lib.protocol")
local nodes = require("lib.nodes")
local moduleRouter = require("lib.module_router")
local machineInfo = require("lib.machine")
local display = require("lib.display")

local modem = protocol.findWirelessModem()
if not modem then error("Wireless modem introuvable") end

local machine = machineInfo.get("collector")
local nodeBus = nodes.new(modem, "collector")
local router = moduleRouter.new()

local loaded = {}
local moduleData = {}
local localEvents = {}
local MAX_LOCAL_EVENTS = (config.events and config.events.historySize) or 30

local monitor = nil
local monitorName = nil
local monitorPage = "control"

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
    emit = emit,
}

local function loadModule(name)
    local ok, mod = pcall(require, "modules." .. name)
    if not ok then
        emit("core.collector", "critical", "MODULE_LOAD_ERROR",
            "Unable to load " .. tostring(name) .. ": " .. tostring(mod))
        return
    end

    if type(mod) ~= "table" then
        emit("core.collector", "critical", "MODULE_LOAD_ERROR",
            tostring(name) .. " did not return a module table")
        return
    end

    local id = mod.id or name
    loaded[id] = mod

    router:register(id, function(message)
        if mod.handleCommand then
            local okCall, err = pcall(mod.handleCommand, message, ctx)
            if not okCall then
                emit(id, "critical", "COMMAND_ERROR", tostring(err))
            end
        end
    end)

    if mod.init then
        local okInit, a, b = pcall(mod.init, ctx)
        if not okInit or a == false then
            emit(id, "critical", "MODULE_INIT_ERROR", tostring(not okInit and a or b))
            loaded[id] = nil
            return
        end
    end

    emit(id, "success", "MODULE_LOADED", "Collector module loaded")
end

for _, name in ipairs((config.collector and config.collector.modules) or {}) do
    loadModule(name)
end

modem.open(config.channels.control)
if config.channels.moduleControl then modem.open(config.channels.moduleControl) end

local function findConfiguredMonitor()
    if not (config.localDisplay and config.localDisplay.enabled) then return nil, nil end

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
    if nextName == monitorName and monitor then return end

    if monitor then pcall(display.shutdown, monitor) end
    monitor = nextMonitor
    monitorName = nextName

    if monitor then
        local ok = pcall(display.init, monitor)
        if not ok then monitor = nil end
    end
end

local function displayModule()
    local id = config.collector and config.collector.displayModule
    if not id then return nil, nil end
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

    local mod, data = displayModule()
    if not mod then
        monitor.setBackgroundColor(colors.black)
        monitor.setTextColor(colors.orange)
        monitor.clear()
        monitor.setCursorPos(1,1)
        monitor.write("No display module")
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
    debug.machineLabel = machine.label or machine.name or machine.key

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
    print("Role    : collector")
    print("")
    print("Modules:")

    local names = {}
    for id in pairs(loaded) do table.insert(names, id) end
    table.sort(names)
    if #names == 0 then
        print("  (none)")
    else
        for _, id in ipairs(names) do
            local state = moduleData[id] and "DATA" or "WAIT"
            print("  " .. id .. " [" .. state .. "]")
        end
    end

    if localEvents[1] then
        print("")
        print("Last: " .. tostring(localEvents[1].code) .. " - " .. tostring(localEvents[1].message))
    end
end

local tickSeconds = (config.timing and config.timing.collectorTick) or 0.50
local timer = os.startTimer(tickSeconds)
redrawTerminal()
redrawMonitor()

while true do
    local event, p1, p2, p3, p4 = os.pullEvent()

    if event == "modem_message" then
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
                local moduleId = config.collector and config.collector.displayModule
                if moduleId then
                    router:dispatch(protocol.makeModuleCommand(
                        moduleId, arg, machine.key, nil, {}, machine.key
                    ))
                end
            end

            redrawMonitor()
        end

    elseif event == "peripheral" or event == "peripheral_detach" then
        refreshDisplay()
        for _, mod in pairs(loaded) do
            if mod.peripheralChanged then pcall(mod.peripheralChanged, event, p1, ctx) end
        end
        redrawMonitor()

    elseif event == "timer" and p1 == timer then
        nodeBus:tick()

        for id, mod in pairs(loaded) do
            if mod.update then
                local ok, err = pcall(mod.update, ctx)
                if not ok then emit(id, "critical", "MODULE_UPDATE_ERROR", tostring(err)) end
            end

            if mod.collect then
                local ok, data = pcall(mod.collect, ctx)
                if ok and type(data) == "table" then
                    data.type = data.type or "module_telemetry"
                    data.network = machine.network
                    data.module = data.module or id
                    data.machine = machine.key
                    data.timestamp = data.timestamp or protocol.now()
                    moduleData[id] = data

                    protocol.send(modem, config.channels.telemetry, data)
                    if config.channels.moduleData and config.channels.moduleData ~= config.channels.telemetry then
                        protocol.send(modem, config.channels.moduleData, data)
                    end
                elseif not ok then
                    emit(id, "critical", "COLLECT_ERROR", tostring(data))
                end
            end
        end

        redrawTerminal()
        redrawMonitor()
        timer = os.startTimer(tickSeconds)
    end
end
