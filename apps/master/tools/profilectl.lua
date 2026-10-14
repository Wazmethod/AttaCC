local config = require("lib.config")
local machineInfo = require("lib.machine")
local profileStore = require("lib.profile_store")

local args = { ... }
if profileStore.handleCli(args) then return end
local cmd = args[1] or "status"
local PROFILE_FILE = "/etc/profile.lua"

local function quote(value)
    return string.format("%q", tostring(value or ""))
end

local function serialize(value, indent)
    indent = indent or ""
    local t = type(value)
    if t == "string" then return quote(value) end
    if t == "number" or t == "boolean" then return tostring(value) end
    if t ~= "table" then return "nil" end

    local isArray, max = true, 0
    for k in pairs(value) do
        if type(k) ~= "number" then isArray = false break end
        if k > max then max = k end
    end

    local lines, child = { "{" }, indent .. "    "
    if isArray then
        for i=1,max do table.insert(lines, child .. serialize(value[i], child) .. ",") end
    else
        local keys = {}
        for k in pairs(value) do table.insert(keys, k) end
        table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
        for _,k in ipairs(keys) do
            local key = tostring(k):match("^[%a_][%w_]*$")
                and tostring(k) or ("[" .. quote(k) .. "]")
            table.insert(lines, child .. key .. " = " .. serialize(value[k], child) .. ",")
        end
    end
    table.insert(lines, indent .. "}")
    return table.concat(lines, "\n")
end

local function loadProfile()
    if not fs.exists(PROFILE_FILE) then return {} end
    local ok, value = pcall(dofile, PROFILE_FILE)
    return ok and type(value) == "table" and value or {}
end

local function writeProfile(profile)
    local ok, detail = profileStore.saveProfile(profile)
    if not ok then error(detail) end
    if detail and detail ~= "local" and detail ~= "synced" then
        print("Config: " .. tostring(detail))
    end
end

local function prompt(label, current)
    write(label .. " [" .. tostring(current or "") .. "]: ")
    local value = read()
    return value == "" and current or value
end

local function promptBool(label, current)
    write(label .. " [" .. (current and "Y/n" or "y/N") .. "]: ")
    local value = read():lower()
    if value == "" then return current end
    if value == "y" or value == "yes" or value == "1" or value == "true" then return true end
    if value == "n" or value == "no" or value == "0" or value == "false" then return false end
    return current
end

local function editProfile()
    if not fs.exists(PROFILE_FILE) then writeProfile({}) end
    shell.run("edit", PROFILE_FILE)
    local edited = loadProfile()
    writeProfile(edited)
end

local function resetProfile()
    if not fs.exists(PROFILE_FILE) then print("No local profile to remove."); return end
    write("Delete local profile? [y/N] ")
    local answer = read():lower()
    if answer == "y" or answer == "yes" then fs.delete(PROFILE_FILE); print("Profile removed.")
    else print("Cancelled.") end
end

local machine = machineInfo.get("master")

if cmd == "status" then
    local home = config.master and config.master.home or {}
    print("Machine     : " .. tostring(machine.key))
    print("Network     : " .. tostring(machine.network))
    print("Display     : " .. tostring(config.display and config.display.preferred))
    print("History     : " .. tostring(config.master and config.master.historySamples or 120) .. " samples")
    print("Home        : machines=" .. tostring(home.machines ~= false)
        .. " network=" .. tostring(home.network ~= false)
        .. " events=" .. tostring(home.events ~= false)
        .. " storage=" .. tostring(home.storage ~= false)
        .. " web=" .. tostring(home.web ~= false))
    print("Storage     : " .. tostring(config.storage and config.storage.backend or "auto")
        .. " label=" .. tostring(config.storage and config.storage.driveLabel or "ATTACC_STORAGE"))
    print("Profile file: " .. (fs.exists(PROFILE_FILE) and PROFILE_FILE or "(defaults)"))
    return
end

if cmd == "edit" or cmd == "show" then editProfile(); return end

if cmd == "home" then
    local profile = loadProfile()
    profile.master = profile.master or {}
    profile.master.home = profile.master.home or {}

    local current = config.master and config.master.home or {}
    print("Master HOME widgets")
    print("-------------------")
    profile.master.home.machines = promptBool("Machines", current.machines ~= false)
    profile.master.home.network = promptBool("Network", current.network ~= false)
    profile.master.home.events = promptBool("Recent events", current.events ~= false)
    profile.master.home.storage = promptBool("Storage", current.storage ~= false)
    profile.master.home.web = promptBool("Web bridge", current.web ~= false)

    writeProfile(profile)
    print("HOME configuration saved. Reboot the Master to apply it.")
    return
end

if cmd == "storage" then
    local profile = loadProfile()
    profile.storage = profile.storage or {}
    print("Storage backend")
    print("---------------")
    profile.storage.backend = prompt("Backend (auto/local/drive)",
        config.storage and config.storage.backend or "auto")
    profile.storage.driveLabel = prompt("Drive media label",
        config.storage and config.storage.driveLabel or "ATTACC_STORAGE")
    local currentName = config.storage and config.storage.driveName or ""
    local name = prompt("Pinned drive peripheral (blank = any)", currentName)
    profile.storage.driveName = name ~= "" and name or nil
    profile.storage.drivePath = prompt("Path on data disk",
        config.storage and config.storage.drivePath or "attacc/storage/store.json")
    writeProfile(profile)
    print("Storage configuration saved. Reboot recommended.")
    return
end

if cmd == "init" then
    local profile = loadProfile()
    profile.master = profile.master or {}
    profile.display = profile.display or {}
    profile.master.historySamples = tonumber(prompt("Graph history samples",
        config.master and config.master.historySamples or 120)) or 120
    profile.display.preferred = prompt("Display backend",
        config.display and config.display.preferred or "auto")
    writeProfile(profile)
    print("Master profile saved.")
    print("Use 'profilectl home' for HOME widgets and 'profilectl storage' for storage.")
    print("Reboot recommended.")
    return
end

if cmd == "reset" then resetProfile(); return end

print("Usage:")
print("  profilectl status")
print("  profilectl init")
print("  profilectl home")
print("  profilectl storage")
print("  profilectl edit")
print("  profilectl reset")
