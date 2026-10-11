local config = require("lib.config")
local machineInfo = require("lib.machine")

local args = { ... }
local cmd = args[1] or "status"
local PROFILE_FILE = ".infra/config/profile.lua"

local function ensureParent()
    local dir = fs.getDir(PROFILE_FILE)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
end

local function ensureProfile()
    if fs.exists(PROFILE_FILE) then return end
    ensureParent()
    local h = fs.open(PROFILE_FILE, "w")
    if not h then error("Cannot create " .. PROFILE_FILE) end
    h.write("return {}\n")
    h.close()
end

local function setting(section, key, fallback)
    local ws = config.workstation or {}
    local s = ws[section] or {}
    local value = s[key]
    if value == nil then return fallback end
    return value
end

local function displaySetting(key, fallback)
    local s = config.standaloneDisplay or {}
    local value = s[key]
    if value == nil then return fallback end
    return value
end

local function promptPeripheral(label, section, expected)
    local currentEnabled = setting(section, "enabled", true)
    local current = currentEnabled and setting(section, "peripheral", "auto") or "none"
    write(label .. " [auto/name/none] [" .. tostring(current) .. "]: ")
    local value = read()
    if value == "" then value = current end

    if value == "none" or value == "disabled" then
        return false, "auto"
    end

    if value ~= "auto" then
        if peripheral.isPresent(value) then
            local types = { peripheral.getType(value) }
            local good = false
            for _, t in ipairs(types) do if t == expected then good = true break end end
            if not good then
                print("Warning: " .. tostring(value) .. " is not type " .. expected .. ".")
                print("The module will stay inactive until profile and hardware match.")
            end
        else
            print("Warning: " .. tostring(value) .. " is not currently present.")
        end
    end

    return true, value
end

local function writeProfile(consoleEnabled, consolePeripheral, displayEnabled, displayPeripheral)
    ensureParent()
    local h = fs.open(PROFILE_FILE .. ".new", "w")
    if not h then error("Cannot write profile") end
    h.write("return {\n")
    h.write("    workstation = {\n")
    h.write("        console = { enabled = " .. tostring(consoleEnabled)
        .. ", peripheral = " .. string.format("%q", consolePeripheral) .. " },\n")
    h.write("    },\n")
    h.write("    standaloneDisplay = { enabled = " .. tostring(displayEnabled)
        .. ", peripheral = " .. string.format("%q", displayPeripheral)
        .. ", textScale = 0.5 },\n")
    h.write("}\n")
    h.close()
    if fs.exists(PROFILE_FILE) then fs.delete(PROFILE_FILE) end
    fs.move(PROFILE_FILE .. ".new", PROFILE_FILE)
end

if cmd == "status" then
    local machine = machineInfo.get("workstation")
    print("Preset      : " .. tostring(machine.preset or "workstation"))
    print("Hostname    : " .. tostring(machine.hostname))
    print("Machine     : " .. tostring(machine.key))
    print("Network     : " .. tostring(machine.network))
    print("Services    : " .. table.concat(machine.services or {}, ", "))
    print("Modules     : " .. table.concat(machine.modules or {}, ", "))
    print("Profile file: " .. (fs.exists(PROFILE_FILE) and PROFILE_FILE or "(defaults)"))
    print("Console     : " .. (setting("console", "enabled", true) and tostring(setting("console", "peripheral", "auto")) or "disabled"))
    print("Display     : " .. (displaySetting("enabled", true) and tostring(displaySetting("peripheral", "auto")) or "disabled"))
    return
end

if cmd == "edit" or cmd == "show" then
    ensureProfile()
    shell.run("edit", PROFILE_FILE)
    return
end

if cmd == "init" then
    local ce, cp = promptPeripheral("Console terminal", "console", "terminal")

    local currentDisplay = displaySetting("enabled", true)
        and displaySetting("peripheral", "auto") or "none"
    write("Display monitor [auto/name/none] [" .. tostring(currentDisplay) .. "]: ")
    local dp = read()
    if dp == "" then dp = currentDisplay end
    local de = dp ~= "none" and dp ~= "disabled"
    if not de then dp = "auto" end

    writeProfile(ce, cp, de, dp)
    print("")
    print("Workstation profile saved.")
    print("Reboot recommended.")
    return
end

if cmd == "reset" then
    if not fs.exists(PROFILE_FILE) then
        print("No local profile to remove.")
        return
    end
    write("Delete local profile? [y/N] ")
    local answer = read():lower()
    if answer == "y" or answer == "yes" then
        fs.delete(PROFILE_FILE)
        print("Profile removed.")
    else
        print("Cancelled.")
    end
    return
end

print("Usage:")
print("  profilectl status")
print("  profilectl init")
print("  profilectl edit")
print("  profilectl reset")
