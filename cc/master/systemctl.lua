local runtime = require("lib.runtime")
local serviceManager = require("lib.services")
local moduleManager = require("lib.modules")
local config = require("lib.config")
local machineInfo = require("lib.machine")
local serviceBoot = require("lib.service_boot")
local paths = require("lib.paths")

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
    if d < 3600000 then return string.format("%.1fmin", d / 60000) end
    if d < 86400000 then return string.format("%.1fh", d / 3600000) end
    return string.format("%.1fd", d / 86400000)
end

local function date(ms)
    if not ms then return "-" end
    local sec = math.floor(ms / 1000)
    local ok, value = pcall(os.date, "%Y-%m-%d %H:%M:%S", sec)
    if ok and value then return value end
    return tostring(sec)
end

local function runtimeEntry(serviceName)
    local snap = runtime.snapshot()
    return snap.services and snap.services["service:" .. serviceName] or nil
end

local function binaryStillRequired(binary, exceptName)
    if not binary then return false end
    for _, otherName in ipairs(serviceManager.names()) do
        if otherName ~= exceptName then
            local other = serviceManager.status(otherName)
            if other and other.active and other.binary == binary then return true end
        end
    end
    return false
end

local function stopBinaryIfUnused(service, serviceName)
    if not service or not service.binary or not multishell then return end
    if binaryStillRequired(service.binary, serviceName) then return end
    os.queueEvent("infra_service_stop", service.binary)
end

local function moduleListForService(serviceName, service)
    local out, seen = {}, {}

    local function add(moduleName)
        moduleName = tostring(moduleName or ""):gsub("%.mod$", "")
        if moduleName ~= "" and not seen[moduleName] then
            seen[moduleName] = true
            table.insert(out, moduleName .. ".mod")
        end
    end

    for _, moduleName in ipairs((service and service.modules) or {}) do add(moduleName) end

    for _, moduleName in ipairs(moduleManager.names()) do
        local def = moduleManager.definition(moduleName)
        for _, requirement in ipairs((def and def.requires) or {}) do
            if normalizeServiceName(requirement) == serviceName then add(moduleName) end
        end
    end

    table.sort(out)
    return out
end

local function effectiveState(serviceName, s, live)
    if live and live.status then return tostring(live.status) end
    if not s.enabled then return "disabled" end
    if not s.active then return "inactive" end
    if s.binary then return "starting" end
    return "active"
end

local function activeDescription(state, s)
    if state == "failed" then return "failed (Result: exit-code)" end
    if state == "active" then
        return s.binary and "active (running)" or "active (embedded)"
    end
    if state == "starting" then return "activating (start)" end
    if state == "exited" then return "inactive (exited)" end
    if state == "stopping" then return "deactivating (stop)" end
    if state == "disabled" then return "inactive (disabled)" end
    return tostring(state)
end

local function loadedDescription(s)
    local source = s.unitPath or "(generated from preset/runtime)"
    local enabled = s.enabled and "enabled" or "disabled"
    local value = "loaded (" .. tostring(source) .. "; " .. enabled .. ")"
    if s.configPath then
        value = value .. "\n     Drop-In: " .. tostring(s.configPath)
    end
    return value
end

local function printLogs(serviceName, count)
    local entries = runtime.logs(count or 5, "service:" .. serviceName)
    if #entries == 0 then
        print("")
        print("No journal entries.")
        return
    end

    print("")
    for _, entry in ipairs(entries) do
        local stamp = date(entry.timestamp)
        print(string.format("%s %-7s %s: %s",
            stamp,
            tostring(entry.level or "info"),
            tostring(machine.hostname or machine.key),
            tostring(entry.message or "")))
    end
end

local function printStatus(serviceName)
    serviceManager.syncRuntime()
    moduleManager.syncRuntime()

    local s = serviceManager.status(serviceName)
    if not s then error("Unknown service: " .. tostring(serviceName)) end
    local live = runtimeEntry(serviceName)
    local state = effectiveState(serviceName, s, live)
    local marker = state == "failed" and "x" or (state == "active" and "*" or "-")

    print(marker .. " " .. serviceName .. ".service - " .. tostring(s.description or "-"))
    print("     Loaded: " .. loadedDescription(s))
    print("     Active: " .. activeDescription(state, s)
        .. (live and live.since and (" since " .. date(live.since) .. "; " .. age(live.since) .. " ago") or ""))
    print("    Process: " .. tostring(s.binary or "(embedded)"))
    if live and live.pid then print("        PID: " .. tostring(live.pid)) end

    local modules = moduleListForService(serviceName, s)
    print("    Modules: " .. (#modules > 0 and table.concat(modules, " ") or "-"))

    local deps = {}
    for _, dep in ipairs(s.depends or {}) do table.insert(deps, dep .. ".service") end
    print("   Requires: " .. (#deps > 0 and table.concat(deps, " ") or "-"))

    if not s.dependenciesOk then
        print("    Blocked: " .. tostring(s.missingDependency) .. ".service")
    end
    if s.conditionOk == false then
        print("  Condition: missing " .. tostring(s.missingCondition))
    end

    print("       Logs: " .. tostring(runtime.logPath("service:" .. serviceName)))
    printLogs(serviceName, tonumber(args[3]) or 5)
end

local function listServices()
    serviceManager.syncRuntime()
    print("SYSTEM SERVICES")
    print("Machine : " .. tostring(machine.key))
    print("Preset  : " .. tostring(machine.preset or "-"))
    print("")
    print(string.format("   %-24s %-12s %-18s %s", "UNIT", "STATE", "BINARY", "DESCRIPTION"))

    for _, serviceName in ipairs(serviceManager.names()) do
        local s = serviceManager.status(serviceName)
        local live = runtimeEntry(serviceName)
        local state = effectiveState(serviceName, s, live)
        local marker = state == "active" and "[+]"
            or state == "failed" and "[x]"
            or state == "starting" and "[~]"
            or s.enabled and "[!]" or "[-]"

        print(string.format("%s %-24s %-12s %-18s %s",
            marker,
            serviceName .. ".service",
            state,
            tostring(s.binary or "(embedded)"),
            tostring(s.description or "")))
    end
end

local function serviceConfigPath(serviceName)
    return fs.combine(paths.serviceConfig, serviceName .. ".conf.lua")
end

local function ensureServiceConfig(serviceName)
    local path = serviceConfigPath(serviceName)
    if fs.exists(path) then return path end
    if not serviceManager.definition(serviceName) then error("Unknown service: " .. tostring(serviceName)) end
    if not fs.exists(paths.serviceConfig) then fs.makeDir(paths.serviceConfig) end
    local h = fs.open(path, "w")
    if not h then error("Cannot create " .. path) end
    h.write("return {\n")
    h.write("    name = " .. string.format("%q", serviceName) .. ",\n")
    h.write("    -- enabled = true,\n")
    h.write("    -- binary = nil,\n")
    h.write("    -- depends = {},\n")
    h.write("    -- requiresFile = nil,\n")
    h.write("}\n")
    h.close()
    return path
end

if cmd == "list" or (cmd == "status" and not name) then
    listServices()
    return
end

if cmd == "status" and name then
    printStatus(name)
    return
end

if cmd == "enable" and name then
    local ok, err = serviceManager.enable(name)
    if not ok then error(err) end
    print("Enabled " .. name .. ".service")
    return
end

if cmd == "disable" and name then
    local ok, err = serviceManager.disable(name)
    if not ok then error(err) end
    print("Disabled " .. name .. ".service")
    return
end

if cmd == "start" and name then
    local ok, err = serviceManager.start(name)
    if not ok then error(err) end
    serviceManager.syncRuntime()
    if multishell then serviceBoot.launchTabs() end
    print("Started " .. name .. ".service")
    return
end

if cmd == "stop" and name then
    local before = serviceManager.status(name)
    local ok, err = serviceManager.stop(name)
    if not ok then error(err) end
    serviceManager.syncRuntime()
    stopBinaryIfUnused(before, name)
    print("Stopped " .. name .. ".service")
    return
end

if cmd == "restart" and name then
    local before = serviceManager.status(name)
    local ok, err = serviceManager.restart(name)
    if not ok then error(err) end
    serviceManager.syncRuntime()
    stopBinaryIfUnused(before, name)
    sleep(0.6)
    local startOk, startErr = serviceManager.start(name)
    if not startOk then error(startErr) end
    serviceManager.syncRuntime()
    if multishell then serviceBoot.launchTabs() end
    print("Restarted " .. name .. ".service")
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
    if name then
        printLogs(name, tonumber(args[3]) or 50)
    else
        for _, entry in ipairs(runtime.logs(tonumber(args[2]) or 50)) do
            print(string.format("%s %-7s %-22s %s",
                date(entry.timestamp),
                tostring(entry.level),
                tostring(entry.service),
                tostring(entry.message)))
        end
    end
    return
end

if cmd == "cat" and name then
    local s = serviceManager.status(name)
    if not s then error("Unknown service: " .. tostring(name)) end
    if s.unitPath and fs.exists(s.unitPath) then
        shell.run("cat", s.unitPath)
    else
        print("-- generated service definition --")
        print(textutils.serialize(serviceManager.definition(name)))
    end
    if s.configPath and fs.exists(s.configPath) then
        print("")
        print("-- local override: " .. s.configPath .. " --")
        shell.run("cat", s.configPath)
    end
    return
end

if cmd == "edit" and name then
    shell.run("edit", ensureServiceConfig(name))
    return
end

if cmd == "daemon-reload" then
    serviceManager.syncRuntime()
    moduleManager.syncRuntime()
    print("Reloaded service and module definitions.")
    return
end

if cmd == "config" then
    print("CONFIGURATION")
    print("Machine   : /etc/infra/machine.lua")
    print("Profile   : /etc/infra/profile.lua")
    print("Services  : /etc/infra/services/*.conf.lua")
    print("Units     : /usr/lib/infra/systemd + /etc/infra/systemd")
    print("Modules   : /usr/lib/infra/modules + /etc/infra/modules")
    print("Logs      : /var/log/infra")
    print("Network   : " .. tostring(machine.network) .. " (" .. tostring(machine.networkLabel) .. ")")
    print("Preset    : " .. tostring(machine.preset or "-"))
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
print("  systemctl start|stop|restart <service>")
print("  systemctl enable|disable|is-enabled <service>")
print("  systemctl dependencies <service>")
print("  systemctl logs [service] [count]")
print("  systemctl cat <service>")
print("  systemctl edit <service>")
print("  systemctl daemon-reload")
print("  systemctl config")
print("  systemctl profile")
