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

if cmd == "status" then
    local machine = machineInfo.get("workstation")
    print("Preset      : " .. tostring(machine.preset or "workstation"))
    print("Hostname    : " .. tostring(machine.hostname))
    print("Machine     : " .. tostring(machine.key))
    print("Network     : " .. tostring(machine.network))
    print("Services    : " .. table.concat(machine.services or {}, ", "))
    print("Modules     : " .. table.concat(machine.modules or {}, ", "))
    print("Profile file: " .. (fs.exists(PROFILE_FILE) and PROFILE_FILE or "(defaults)"))
    return
end

if cmd == "edit" or cmd == "show" then
    ensureProfile()
    shell.run("edit", PROFILE_FILE)
    return
end

if cmd == "init" then
    ensureProfile()
    print("Workstation profile initialized.")
    print("Use 'profilectl edit' for optional overrides.")
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
