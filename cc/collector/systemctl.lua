local runtime = require("lib.runtime")
local serviceManager = require("lib.services")
local config = require("lib.config")
local machineInfo = require("lib.machine")

local args = { ... }
local cmd = args[1] or "list"
local name = args[2]
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

local function printStatus(name)
    local s = serviceManager.status(name)
    if not s then error("Unknown service: " .. tostring(name)) end
    local live = runtimeEntry(name)

    print("Service      : " .. tostring(name))
    print("Description  : " .. tostring(s.description or "-"))
    print("Preset       : " .. tostring(machine.preset or "-"))
    print("Enabled      : " .. tostring(s.enabled))
    print("Active       : " .. tostring(s.active))
    print("Protected    : " .. tostring(s.protected))
    print("Dependencies : " .. (#s.depends > 0 and table.concat(s.depends, ", ") or "-"))
    if not s.dependenciesOk then
        print("Blocked by   : " .. tostring(s.missingDependency))
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
    for _, serviceName in ipairs(serviceManager.names()) do
        local s = serviceManager.status(serviceName)
        local marker = s.active and "[+]" or (s.enabled and "[!]" or "[-]")
        local state = s.active and "active" or (s.enabled and "inactive" or "disabled")
        print(string.format("%s %-16s %-10s %s",
            marker, serviceName, state, tostring(s.description or "")))
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
        for _, dep in ipairs(s.depends) do print(dep) end
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
    print("Services : " .. table.concat(serviceManager.capabilities(), ", "))

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
    if not fs.exists("profile.local.lua") then
        local h = fs.open("profile.local.lua", "w")
        h.write("return {}\n")
        h.close()
    end
    shell.run("edit", "profile.local.lua")
    print("Configuration saved. Runtime service gates are read live; other profile changes may require reboot.")
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
