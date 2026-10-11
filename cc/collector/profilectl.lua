local config = require("lib.config")
local machineInfo = require("lib.machine")

local args = { ... }
local cmd = args[1] or "status"
local machine = machineInfo.get()

local function quote(value)
    return string.format("%q", tostring(value or ""))
end

local function splitCsv(value)
    local out = {}
    for item in tostring(value or ""):gmatch("[^,]+") do
        item = item:match("^%s*(.-)%s*$")
        if item ~= "" then table.insert(out, item) end
    end
    return out
end

local function join(list)
    return table.concat(type(list) == "table" and list or {}, ",")
end

local function serialize(value, indent)
    indent = indent or ""
    local t = type(value)

    if t == "string" then return quote(value) end
    if t == "number" or t == "boolean" then return tostring(value) end
    if t ~= "table" then return "nil" end

    local isArray = true
    local max = 0
    for k in pairs(value) do
        if type(k) ~= "number" then isArray = false break end
        if k > max then max = k end
    end

    local lines = { "{" }
    local child = indent .. "    "

    if isArray then
        for i = 1, max do
            table.insert(lines, child .. serialize(value[i], child) .. ",")
        end
    else
        local keys = {}
        for k in pairs(value) do table.insert(keys, k) end
        table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local key = tostring(k):match("^[%a_][%w_]*$") and tostring(k) or ("[" .. quote(k) .. "]")
            table.insert(lines, child .. key .. " = " .. serialize(value[k], child) .. ",")
        end
    end

    table.insert(lines, indent .. "}")
    return table.concat(lines, "\n")
end

local function mergeTables(base, override)
    base = type(base) == "table" and base or {}
    if type(override) ~= "table" then return base end

    for k, v in pairs(override) do
        if type(v) == "table" and type(base[k]) == "table" then
            base[k] = mergeTables(base[k], v)
        else
            base[k] = v
        end
    end
    return base
end

local function loadExistingProfile()
    if not fs.exists("profile.local.lua") then return {} end
    local ok, value = pcall(dofile, "profile.local.lua")
    if ok and type(value) == "table" then return value end
    return {}
end

local function writeProfile(profile)
    local tmp = "profile.local.lua.new"
    local h = fs.open(tmp, "w")
    if not h then error("Cannot write " .. tmp) end
    h.write("return " .. serialize(profile) .. "\n")
    h.close()

    if fs.exists("profile.local.lua") then fs.delete("profile.local.lua") end
    fs.move(tmp, "profile.local.lua")
end

local function prompt(label, current)
    write(label .. " [" .. tostring(current or "") .. "]: ")
    local value = read()
    return value == "" and current or value
end

local function printStatus()
    print("Role        : " .. tostring(machine.role))
    print("Machine     : " .. tostring(machine.key))
    print("Network     : " .. tostring(machine.network))
    print("Profile file: " .. (fs.exists("profile.local.lua") and "profile.local.lua" or "(defaults)"))

    if machine.role == "collector" then
        print("Modules     : " .. join(config.collector and config.collector.modules))
        print("Display mod : " .. tostring(config.collector and config.collector.displayModule))
        print("RPM mult    : " .. tostring(config.sensors and config.sensors.rpm and config.sensors.rpm.multiplier or 1))
        print("Motor dir   : " .. tostring(config.motor and config.motor.direction or 1))
        print("Text pages  : " .. join(config.display and config.display.textPages))
        print("Peripherals :")
        for _, key in ipairs({ "target","speedometer","stressometer","motor","accumulator","redstoneRelay" }) do
            print("  " .. key .. " = " .. tostring(config.peripherals and config.peripherals[key] or "auto"))
        end
    elseif machine.role == "pocket" then
        print("Source mod  : " .. tostring(config.pocket and config.pocket.sourceModule))
        print("Dashboard   : " .. tostring(config.pocket and config.pocket.dashboard))
        print("Transport   : " .. tostring(config.pocket and config.pocket.transport))
        print("Pages       : " .. join(config.pocket and config.pocket.pages))
        print("Display     : " .. tostring(config.display and config.display.preferred))
    elseif machine.role == "master" then
        print("Source mod  : " .. tostring(config.master and config.master.sourceModule))
        print("Pages       : " .. join(config.master and config.master.pages))
        print("Display     : " .. tostring(config.display and config.display.preferred))
    elseif machine.role == "controller" then
        print("Modules     : " .. join(config.controller and config.controller.modules))
        print("Tick        : " .. tostring(config.controller and config.controller.tick))
    end
end

local function initCollector()
    local current = config.collector or {}
    local modules = splitCsv(prompt("Collector modules", join(current.modules)))
    local displayModule = prompt("Display module (blank text 'none' to disable)", current.displayModule or "steamplant")
    if displayModule == "none" then displayModule = nil end

    local rpmMultiplier = tonumber(prompt("RPM sensor multiplier (1/-1)",
        config.sensors and config.sensors.rpm and config.sensors.rpm.multiplier or 1)) or 1
    rpmMultiplier = rpmMultiplier < 0 and -1 or 1

    local motorDirection = tonumber(prompt("Motor direction (1/-1)",
        config.motor and config.motor.direction or 1)) or 1
    motorDirection = motorDirection < 0 and -1 or 1

    local textPages = splitCsv(prompt("Text pages",
        join(config.display and config.display.textPages or { "control", "gen", "data", "logs" })))

    local peripherals = {}
    print("Peripheral names: leave blank to keep auto-discovery.")
    for _, key in ipairs({ "target","speedometer","stressometer","motor","accumulator","redstoneRelay" }) do
        write("  " .. key .. " [" .. tostring(config.peripherals and config.peripherals[key] or "auto") .. "]: ")
        local value = read()
        if value ~= "" and value ~= "auto" then peripherals[key] = value end
    end

    return {
        collector = {
            modules = modules,
            displayModule = displayModule,
        },
        peripherals = peripherals,
        sensors = {
            rpm = {
                multiplier = rpmMultiplier,
            },
        },
        motor = {
            direction = motorDirection,
        },
        display = {
            textPages = textPages,
        },
    }
end

local function initPocket()
    local p = config.pocket or {}
    local source = prompt("Source module", p.sourceModule or "steamplant")
    local dashboard = prompt("Dashboard plugin", p.dashboard or "steamplant")
    local transport = prompt("Transport (master/direct)", p.transport or "master")
    local pages = splitCsv(prompt("Pages", join(p.pages)))
    local preferred = prompt("Display backend (auto/text/ccgraphics)", config.display and config.display.preferred or "auto")

    return {
        pocket = {
            sourceModule = source,
            dashboard = dashboard,
            transport = transport,
            pages = pages,
        },
        display = {
            preferred = preferred,
        },
    }
end

local function initMaster()
    local p = config.master or {}
    local source = prompt("Source module", p.sourceModule or "steamplant")
    local pages = splitCsv(prompt("Pages", join(p.pages)))
    local preferred = prompt("Display backend (auto/text/ccgraphics)", config.display and config.display.preferred or "auto")

    return {
        master = {
            sourceModule = source,
            pages = pages,
        },
        display = {
            preferred = preferred,
        },
    }
end

local function initController()
    local c = config.controller or {}
    local modules = splitCsv(prompt("Controller modules", join(c.modules)))
    local tick = tonumber(prompt("Controller tick seconds", c.tick or 0.10)) or 0.10

    return {
        controller = {
            modules = modules,
            tick = tick,
        },
    }
end

if cmd == "status" then
    printStatus()
    return
end

if cmd == "show" then
    if not fs.exists("profile.local.lua") then
        print("No profile.local.lua; role defaults are active.")
        return
    end
    shell.run("edit", "profile.local.lua")
    return
end

if cmd == "init" then
    local profile
    if machine.role == "collector" then profile = initCollector()
    elseif machine.role == "pocket" then profile = initPocket()
    elseif machine.role == "master" then profile = initMaster()
    elseif machine.role == "controller" then profile = initController()
    else error("Unsupported role: " .. tostring(machine.role)) end

    profile = mergeTables(loadExistingProfile(), profile)
    writeProfile(profile)
    print("")
    print("Profile saved to profile.local.lua")
    print("Reboot to apply.")
    return
end

if cmd == "reset" then
    if not fs.exists("profile.local.lua") then
        print("No local profile to remove.")
        return
    end
    write("Delete profile.local.lua? [y/N] ")
    local answer = read():lower()
    if answer == "y" or answer == "yes" then
        fs.delete("profile.local.lua")
        print("Profile removed. Reboot to use role defaults.")
    else
        print("Cancelled.")
    end
    return
end

print("Usage:")
print("  profilectl status")
print("  profilectl init")
print("  profilectl show")
print("  profilectl reset")
