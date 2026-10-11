local runtime = require("lib.runtime")
local serviceManager = require("lib.services")
local config = require("lib.config")
local machineInfo = require("lib.machine")

local args = { ... }
local cmd = args[1] or "list"
local function normalizeServiceName(value)
    if not value then return nil end
    return tostring(value):gsub("%.service$", "")
end

local name = normalizeServiceName(args[2])
local machine = machineInfo.get()

local function age(ms)
    if not ms then return "-" end
    local d = math.max(0, os.epoch("utc") - ms)
    if d < 1000 then return tostring(d) .. "ms" end
    if d < 60000 then return string.format("%.1fs", d / 1000) end
    return string.format("%.1fm", d / 60000)
end

local function runtimeEntry(serviceName)
    local snap = runtime.snapshot()
    return snap.services and snap.services["service:" .. serviceName] or nil
end

local function binaryTitle(binary)
    if not binary then return nil end
    return fs.getName(binary):gsub("%.lua$", "")
end

local function processState(service)
    if not service.binary then return "embedded" end
    if not multishell then return "unknown" end

    local wanted = binaryTitle(service.binary)
    for id = 1, multishell.getCount() do
        local title = multishell.getTitle(id)
        if title == wanted then return "running" end
    end
    return "missing"
end

local function printStatus(name)
    local s = serviceManager.status(name)
    if not s then error("Unknown service: " .. tostring(name)) end
    local live = runtimeEntry(name)

    print("Service      : " .. tostring(name) .. ".service")
    print("Description  : " .. tostring(s.description or "-"))
    print("Binary       : " .. tostring(s.binary or "(embedded/capability)"))
    print("Preset       : " .. tostring(machine.preset or "-"))
    print("Enabled      : " .. tostring(s.enabled))
    print("Active       : " .. tostring(s.active))
    print("Process      : " .. processState(s))
    print("Protected    : " .. tostring(s.protected))
    local deps = {}
    for _, dep in ipairs(s.depends or {}) do table.insert(deps, dep .. ".service") end
    print("Dependencies : " .. (#deps > 0 and table.concat(deps, ", ") or "-"))
    if not s.dependenciesOk then
        print("Blocked by   : " .. tostring(s.missingDependency) .. ".service")
    end
    if s.conditionOk == false then
        print("Condition    : missing " .. tostring(s.missingCondition))
    end
    if live then
        print("Runtime      : " .. tostring(live.status or "-"))
        print("Updated      : " .. age(live.updatedAt))
    end
end

local function listServices()
    serviceManager.syncRuntime()
    print("SYSTEM SERVICES")
    print("Machine : " .. tostring(machine.key))
    print("Preset  : " .. tostring(machine.preset or "-"))
    print("")
    print(string.format("   %-24s %-10s %-9s %s", "UNIT", "STATE", "PROCESS", "DESCRIPTION"))
    for _, serviceName in ipairs(serviceManager.names()) do
        local s = serviceManager.status(serviceName)
        local marker = s.active and "[+]" or (s.enabled and "[!]" or "[-]")
        local state = s.active and "active" or (s.enabled and "inactive" or "disabled")
        local process = processState(s)
        print(string.format("%s %-24s %-10s %-9s %s",
            marker, serviceName .. ".service", state, process, tostring(s.description or "")))
    end
end

if cmd == "list" or (cmd == "status" and not name) then
    listServices()
    return
end

if cmd == "status" and name then
    serviceManager.syncRuntime()
    printStatus(name)
    return
end

if cmd == "enable" and name then
    local ok, err = serviceManager.enable(name)
    if not ok then error(err) end
    print("Enabled " .. name)
    return
end

if cmd == "disable" and name then
    local ok, err = serviceManager.disable(name)
    if not ok then error(err) end
    print("Disabled " .. name)
    return
end

if cmd == "start" and name then
    local ok, err = serviceManager.start(name)
    if not ok then error(err) end
    serviceManager.syncRuntime()
    print("Started " .. name)
    return
end

if cmd == "stop" and name then
    local ok, err = serviceManager.stop(name)
    if not ok then error(err) end
    serviceManager.syncRuntime()
    print("Stopped " .. name)
    return
end

if cmd == "restart" and name then
    local ok, err = serviceManager.restart(name)
    if not ok then error(err) end
    serviceManager.syncRuntime()
    print("Restarted " .. name)
    return
end

if cmd == "is-enabled" and name then
    print(serviceManager.isEnabled(name) and "enabled" or "disabled")
    return
end

if cmd == "dependencies" and name then
    local s = serviceManager.status(name)
    if not s then error("Unknown service: " .. tostring(name)) end
    if #s.depends == 0 then
        print("(none)")
    else
        for _, dep in ipairs(s.depends) do print(dep .. ".service") end
    end
    return
end

if cmd == "logs" then
    local service = name
    if service and serviceManager.definition(service) then service = "service:" .. service end
    local limit = tonumber(args[3]) or (service and 50 or tonumber(args[2])) or 50
    for _, entry in ipairs(runtime.logs(limit, service)) do
        local sec = math.floor((entry.timestamp or 0) / 1000)
        local h = math.floor((sec / 3600) % 24)
        local m = math.floor((sec / 60) % 60)
        local s = sec % 60
        print(string.format("%02d:%02d:%02d %-7s %-22s %s",
            h, m, s, tostring(entry.level), tostring(entry.service), tostring(entry.message)))
    end
    return
end

if cmd == "config" then
    print("CONFIGURATION")
    print("Identity : .infra/config/machine.lua")
    print("Profile  : .infra/config/profile.lua")
    print("Network  : " .. tostring(machine.network) .. " (" .. tostring(machine.networkLabel) .. ")")
    print("Preset   : " .. tostring(machine.preset or "-"))
    local units = {}
    for _, serviceName in ipairs(serviceManager.capabilities()) do table.insert(units, serviceName .. ".service") end
    print("Services : " .. table.concat(units, ", "))

    if config.io and config.io.bindings then
        local names = {}
        for bindingName in pairs(config.io.bindings) do table.insert(names, bindingName) end
        table.sort(names)
        print("I/O      : " .. (#names > 0 and table.concat(names, ", ") or "(none)"))
    end

    if config.collector then
        print("Modules  : " .. table.concat(config.collector.modules or {}, ", "))
        print("Display  : " .. tostring(config.collector.displayModule))
    elseif config.controller then
        print("Modules  : " .. table.concat(config.controller.modules or {}, ", "))
    elseif config.pocket then
        print("Source   : " .. tostring(config.pocket.sourceModule))
        print("Dashboard: " .. tostring(config.pocket.dashboard))
    elseif config.master then
        print("Source   : " .. tostring(config.master.sourceModule))
    end
    return
end

if cmd == "edit" then
    shell.run("profilectl", "edit")
    return
end

if cmd == "profile" then
    shell.run("profilectl", "status")
    return
end

print("Usage:")
print("  systemctl list")
print("  systemctl status <service>")
print("  systemctl start <service>")
print("  systemctl stop <service>")
print("  systemctl restart <service>")
print("  systemctl enable <service>")
print("  systemctl disable <service>")
print("  systemctl is-enabled <service>")
print("  systemctl dependencies <service>")
print("  systemctl logs [service] [count]")
print("  systemctl config")
print("  systemctl edit")
print("  systemctl profile")
