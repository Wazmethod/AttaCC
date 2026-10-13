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
            local key = tostring(k):match("^[%a_][%w_]*$") and tostring(k) or ("[" .. quote(k) .. "]")
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

local function editProfile()
    if not fs.exists(PROFILE_FILE) then writeProfile({}) end
    shell.run("edit", PROFILE_FILE)
end

local function resetProfile()
    if not fs.exists(PROFILE_FILE) then print("No local profile to remove."); return end
    write("Delete local profile? [y/N] ")
    local answer = read():lower()
    if answer == "y" or answer == "yes" then fs.delete(PROFILE_FILE); print("Profile removed.")
    else print("Cancelled.") end
end



local machine = machineInfo.get("pocket")

if cmd == "status" then
    print("Machine     : " .. tostring(machine.key))
    print("Network     : " .. tostring(machine.network))
    print("Source mod  : " .. tostring(config.pocket and config.pocket.sourceModule))
    print("Transport   : " .. tostring(config.pocket and config.pocket.transport))
    print("Display     : " .. tostring(config.display and config.display.preferred))
    print("Profile file: " .. (fs.exists(PROFILE_FILE) and PROFILE_FILE or "(defaults)"))
    return
end

if cmd == "edit" or cmd == "show" then editProfile(); return end

if cmd == "init" then
    local profile = loadProfile()
    profile.pocket = profile.pocket or {}
    profile.display = profile.display or {}
    profile.pocket.sourceModule = prompt("Preferred source module", config.pocket and config.pocket.sourceModule or "steamplant")
    profile.pocket.transport = prompt("Transport (master/direct)", config.pocket and config.pocket.transport or "master")
    profile.display.preferred = prompt("Display backend", config.display and config.display.preferred or "auto")
    writeProfile(profile)
    print("Pocket profile saved. Reboot recommended.")
    return
end

if cmd == "reset" then resetProfile(); return end
print("Usage: profilectl status|init|edit|reset|sync|push|remote <machine> [profile|machine]|machines|storage")
