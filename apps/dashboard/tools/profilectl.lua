local config = require("lib.config")
local machineInfo = require("lib.machine")
local profileStore = require("lib.profile_store")

local args={...}
if profileStore.handleCli(args) then return end

local cmd=args[1] or "status"
local FILE="/etc/profile.lua"

local function loadProfile()
    if not fs.exists(FILE) then return {} end
    local ok,v=pcall(dofile,FILE)
    return ok and type(v)=="table" and v or {}
end

local function save(profile)
    local ok,detail=profileStore.saveProfile(profile)
    if not ok then error(detail) end
    if detail and detail~="local" and detail~="synced" then print("Config: "..tostring(detail)) end
end

local function boolPrompt(label,current)
    write(label.." ["..(current and "Y/n" or "y/N").."]: ")
    local v=read():lower()
    if v=="" then return current end
    if v=="y" or v=="yes" then return true end
    if v=="n" or v=="no" then return false end
    return current
end

local machine=machineInfo.get("dashboard")

if cmd=="status" then
    local home=config.dashboard and config.dashboard.home or {}
    print("Machine : "..tostring(machine.key))
    print("Network : "..tostring(machine.network))
    print("Home    : machines="..tostring(home.machines~=false)
        .." network="..tostring(home.network~=false)
        .." events="..tostring(home.events~=false))
    return
end

if cmd=="home" then
    local profile=loadProfile()
    profile.dashboard=profile.dashboard or {}
    profile.dashboard.home=profile.dashboard.home or {}
    local current=config.dashboard and config.dashboard.home or {}
    profile.dashboard.home.machines=boolPrompt("Machines",current.machines~=false)
    profile.dashboard.home.network=boolPrompt("Network",current.network~=false)
    profile.dashboard.home.events=boolPrompt("Events",current.events~=false)
    save(profile)
    print("Dashboard HOME saved. Reboot recommended.")
    return
end

if cmd=="edit" then
    if not fs.exists(FILE) then save({}) end
    shell.run("edit",FILE)
    save(loadProfile())
    return
end

if cmd=="reset" then
    if fs.exists(FILE) then fs.delete(FILE) end
    print("Local profile removed.")
    return
end

print("Usage: profilectl status|home|edit|reset|sync|push|remote <machine> [profile|machine]|machines|storage-sync")
