local config = require("lib.config")
local protocol = require("lib.protocol")
local machineInfo = require("lib.machine")
local nodes = require("lib.nodes")
local moduleRouter = require("lib.module_router")
local runtime = require("lib.runtime")
local bus = require("lib.bus")
local network = require("lib.network")
local ioRegistry = require("lib.io_registry")
local webcap = require("lib.webcap")

local modem = protocol.findWirelessModem()
if not modem then error("Wireless modem introuvable") end

local machine = machineInfo.get("controller")
local nodeBus = nodes.new(modem, "controller")
local router = moduleRouter.new()
local net = network.new(config, machine)

runtime.set("app:controller", "active", { detail = "AttaCC controller application active" })
runtime.log("controller", "info", "AttaCC controller application started")

local modules = {}
local events = {}

local function emit(moduleName, level, code, message, extra)
    local event = {
        type = "module_event",
        network = machine.network,
        module = moduleName,
        machine = machine.key,
        level = level or "info",
        code = code or "EVENT",
        message = message or "",
        timestamp = protocol.now(),
    }

    if type(extra) == "table" then
        for k, v in pairs(extra) do event[k] = v end
    end

    table.insert(events, 1, event)
    while #events > 32 do table.remove(events) end

    protocol.send(modem, config.channels.moduleEvents or config.channels.events, event)
end

local context = {
    config = config,
    modem = modem,
    machine = machine,
    protocol = protocol,
    bus = bus,
    io = ioRegistry,
    emit = emit,
}

local function loadModule(name)
    local ok, mod = pcall(require, "modules." .. name)
    if not ok then
        emit("core.controller", "critical", "MODULE_LOAD_ERROR",
            "Unable to load " .. tostring(name) .. ": " .. tostring(mod))
        return false
    end

    if type(mod) ~= "table" then
        emit("core.controller", "critical", "MODULE_LOAD_ERROR",
            "Module " .. tostring(name) .. " did not return a table")
        return false
    end

    local moduleId = mod.id or name
    modules[moduleId] = mod
    runtime.set("module:" .. moduleId, "starting", { module = moduleId })

    router:register(moduleId, function(message)
        if mod.handleCommand then
            local okCall, a, b = pcall(mod.handleCommand, message, context)
            if not okCall then
                emit(moduleId, "critical", "COMMAND_ERROR", tostring(a))
                return
            end

            protocol.send(modem, config.channels.moduleAck or config.channels.ack, {
                type = "module_ack",
                network = machine.network,
                module = moduleId,
                machine = machine.key,
                id = message.id,
                command = message.command,
                ok = a ~= false,
                error = a == false and b or nil,
                timestamp = protocol.now(),
            })
        end
    end)

    if mod.init then
        local okInit, err = pcall(mod.init, context)
        if not okInit then
            runtime.set("module:" .. moduleId, "failed", { module = moduleId, detail = tostring(err) })
            runtime.log("module:" .. moduleId, "error", "module init failed: " .. tostring(err))
            emit(moduleId, "critical", "MODULE_INIT_ERROR", tostring(err))
            return false
        end
    end

    runtime.set("module:" .. moduleId, "active", { module = moduleId })
    runtime.log("module:" .. moduleId, "info", "module loaded")
    emit(moduleId, "success", "MODULE_LOADED", "Module loaded")
    return true
end

for _, name in ipairs((config.controller and config.controller.modules) or {}) do
    loadModule(name)
end

modem.open(config.channels.control)
if config.channels.moduleControl then modem.open(config.channels.moduleControl) end

local function redraw()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)

    print(machine.label)
    print("Machine : " .. tostring(machine.key))
    print("Network : " .. tostring(machine.networkLabel) .. " [" .. tostring(machine.network) .. "]")
    print("Preset  : " .. tostring(machine.preset or "automation-node"))
    print("")
    print("Modules:")

    local names = {}
    for name in pairs(modules) do table.insert(names, name) end
    table.sort(names)

    if #names == 0 then
        print("  (none)")
    else
        for _, name in ipairs(names) do print("  - " .. name) end
    end

    if events[1] then
        print("")
        print("Last: " .. tostring(events[1].code) .. " - " .. tostring(events[1].message))
    end
end

local timer = os.startTimer((config.controller and config.controller.tick) or 0.10)
redraw()

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

    elseif event == "timer" and p1 == timer then
        nodeBus:tick()

        for moduleId, mod in pairs(modules) do
            if mod.update then
                local ok, err = pcall(mod.update, context)
                if not ok then
                    runtime.set("module:" .. moduleId, "degraded", { module = moduleId, detail = tostring(err) })
                    runtime.log("module:" .. moduleId, "error", "update failed: " .. tostring(err))
                    emit(moduleId, "critical", "MODULE_UPDATE_ERROR", tostring(err))
                end
            end

            if mod.telemetry then
                local ok, data = pcall(mod.telemetry, context)
                if ok and type(data) == "table" then
                    if mod.ui then
                        if type(mod.ui) == "function" then
                            local okUi, descriptor = pcall(mod.ui, data, context)
                            if okUi and type(descriptor) == "table" then data.ui = descriptor end
                        elseif type(mod.ui) == "table" then
                            data.ui = mod.ui
                        end
                    end

                    data.type = data.type or "module_telemetry"
                    data.network = machine.network
                    data.module = data.module or moduleId
                    data.machine = machine.key
                    data.timestamp = data.timestamp or protocol.now()
                    runtime.set("module:" .. moduleId, "active", { module = moduleId, detail = "telemetry live" })
                    protocol.send(modem, config.channels.moduleData or config.channels.telemetry, data)
                elseif not ok then
                    emit(moduleId, "warning", "TELEMETRY_ERROR", tostring(data))
                end
            end
        end

        local exportedModules = {}
        for moduleId in pairs(modules) do table.insert(exportedModules, moduleId) end
        table.sort(exportedModules)
        webcap.publish("controller", {
            modules = exportedModules,
            moduleCount = #exportedModules,
            lastEvent = events[1] and {
                level = events[1].level,
                code = events[1].code,
                message = events[1].message,
            } or nil,
        })

        redraw()
        timer = os.startTimer((config.controller and config.controller.tick) or 0.10)

    elseif event == "peripheral" or event == "peripheral_detach" then
        local kind = event == "peripheral" and peripheral.getType(p1) or "detached"
        local message = event == "peripheral"
            and ("peripheral attached: " .. tostring(p1) .. " [" .. tostring(kind) .. "]")
            or ("peripheral detached: " .. tostring(p1))
        runtime.log("controller", "info", message)
        emit("core.controller", "info",
            event == "peripheral" and "PERIPHERAL_ATTACHED" or "PERIPHERAL_DETACHED",
            message)
        print("[peripheral] " .. message)

        if event == "peripheral" and kind == "monitor" then
            runtime.set("display:" .. tostring(p1), "active", { device = p1, backend = "terminal" })
        elseif event == "peripheral_detach" then
            runtime.set("display:" .. tostring(p1), "inactive", { device = p1, backend = "none" })
        end

        for moduleId, mod in pairs(modules) do
            if mod.peripheralChanged then
                pcall(mod.peripheralChanged, event, p1, context)
            end
        end
    end
end
