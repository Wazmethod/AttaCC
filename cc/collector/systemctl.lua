local runtime = require("lib.runtime")
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

local function services()
    local snap = runtime.snapshot()
    local out = {}
    for _, service in pairs(snap.services or {}) do
        table.insert(out, service)
    end
    table.sort(out, function(a,b) return tostring(a.name) < tostring(b.name) end)
    return out
end

local function printService(s)
    print("Service : " .. tostring(s.name))
    print("State   : " .. tostring(s.status or "unknown"))
    print("Updated : " .. age(s.updatedAt))
    print("Since   : " .. age(s.since))
    if s.module then print("Module  : " .. tostring(s.module)) end
    if s.backend then print("Backend : " .. tostring(s.backend)) end
    if s.device then print("Device  : " .. tostring(s.device)) end
    if s.detail then print("Detail  : " .. tostring(s.detail)) end
end

if cmd == "list" or cmd == "status" and not name then
    print("SYSTEM SERVICES")
    print("Machine : " .. tostring(machine.key))
    print("Role    : " .. tostring(machine.role))
    print("")
    local list = services()
    if #list == 0 then
        print("No runtime state yet.")
    else
        for _, s in ipairs(list) do
            local marker = s.status == "active" and "[+]"
                or s.status == "degraded" and "[!]"
                or s.status == "failed" and "[x]"
                or s.status == "inactive" and "[-]"
                or "[?]"
            print(string.format("%s %-24s %-10s %s",
                marker, tostring(s.name), tostring(s.status), age(s.updatedAt)))
        end
    end
    return
end

if cmd == "status" and name then
    for _, s in ipairs(services()) do
        if s.name == name then
            printService(s)
            return
        end
    end
    error("Unknown service: " .. tostring(name))
end

if cmd == "logs" then
    local service = name
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
    print("Identity : machine.local.lua")
    print("Profile  : profile.local.lua")
    print("Network  : " .. tostring(machine.network) .. " (" .. tostring(machine.networkLabel) .. ")")
    print("Role     : " .. tostring(machine.role))

    if machine.role == "collector" then
        print("Modules  : " .. table.concat(config.collector and config.collector.modules or {}, ", "))
        print("Display  : " .. tostring(config.collector and config.collector.displayModule))
        if config.sensors and config.sensors.rpm then
            print("RPM x    : " .. tostring(config.sensors.rpm.multiplier or 1))
        end
        if config.motor then
            print("Motor dir: " .. tostring(config.motor.direction or 1))
        end
    elseif machine.role == "controller" then
        print("Modules  : " .. table.concat(config.controller and config.controller.modules or {}, ", "))
    elseif machine.role == "pocket" then
        print("Source   : " .. tostring(config.pocket and config.pocket.sourceModule))
        print("Dashboard: " .. tostring(config.pocket and config.pocket.dashboard))
    elseif machine.role == "master" then
        print("Source   : " .. tostring(config.master and config.master.sourceModule))
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
    print("Configuration saved. Reboot to apply.")
    return
end

if cmd == "profile" then
    shell.run("profilectl", "status")
    return
end

print("Usage:")
print("  systemctl list")
print("  systemctl status [service]")
print("  systemctl logs [service] [count]")
print("  systemctl config")
print("  systemctl edit")
print("  systemctl profile")
