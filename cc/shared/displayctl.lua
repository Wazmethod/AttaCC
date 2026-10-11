local display = require("lib.display_api")
local config = require("lib.config")
local args = { ... }
local cmd = args[1] or "status"
local PROFILE_FILE = ".infra/config/profile.lua"

local function ensureParent()
    local dir = fs.getDir(PROFILE_FILE)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
end

local function loadProfile()
    if not fs.exists(PROFILE_FILE) then return {} end
    local ok, value = pcall(dofile, PROFILE_FILE)
    if ok and type(value) == "table" then return value end
    return {}
end

local function saveProfile(value)
    ensureParent()
    local h = fs.open(PROFILE_FILE .. ".new", "w")
    if not h then return false, "cannot write profile" end
    h.write("return " .. textutils.serialize(value) .. "\n")
    h.close()
    if fs.exists(PROFILE_FILE) then fs.delete(PROFILE_FILE) end
    fs.move(PROFILE_FILE .. ".new", PROFILE_FILE)
    return true
end

local function resolveMonitor()
    local section = config.standaloneDisplay or {}
    if section.enabled == false then return nil, "disabled" end

    local name = section.peripheral
    if name and name ~= "" and name ~= "auto" then
        if not peripheral.isPresent(name) then return nil, "missing: " .. tostring(name) end
        if peripheral.getType(name) ~= "monitor" then return nil, "wrong type: " .. tostring(name) end
        return name
    end

    local mon = peripheral.find("monitor")
    if not mon then return nil, "no monitor found" end
    return peripheral.getName(mon)
end

if cmd == "status" then
    local s = display.status()
    local name, err = resolveMonitor()
    print("Monitor   : " .. tostring(name or err))
    print("Configured: " .. tostring((config.standaloneDisplay and config.standaloneDisplay.peripheral) or "auto"))
    print("Enabled   : " .. tostring(not (config.standaloneDisplay and config.standaloneDisplay.enabled == false)))
    print("Published : " .. tostring(s.published))
    print("Owner     : " .. tostring(s.owner or "(none)"))
    print("View      : " .. tostring(s.selectedView or "(default)"))
    if s.views and #s.views > 0 then
        local labels = {}
        for _, item in ipairs(s.views) do
            table.insert(labels, item.id .. "=" .. item.label)
        end
        print("Views     : " .. table.concat(labels, ", "))
    end
    if s.descriptor then print(textutils.serialize(s.descriptor)) end
    return
end

if cmd == "use" then
    local target = args[2] or "auto"
    local profile = loadProfile()
    profile.standaloneDisplay = profile.standaloneDisplay or {}

    if target == "off" or target == "none" or target == "disabled" then
        profile.standaloneDisplay.enabled = false
        profile.standaloneDisplay.peripheral = "auto"
    else
        profile.standaloneDisplay.enabled = true
        profile.standaloneDisplay.peripheral = target
        if profile.standaloneDisplay.textScale == nil then
            profile.standaloneDisplay.textScale = 0.5
        end
    end

    local ok, err = saveProfile(profile)
    if not ok then error(err) end
    print("Display profile updated.")
    print("Reboot recommended.")
    return
end

if cmd == "detect" then
    local names = peripheral.getNames()
    local found = {}
    for _, name in ipairs(names) do
        local types = { peripheral.getType(name) }
        for _, t in ipairs(types) do
            if t == "monitor" then table.insert(found, name) break end
        end
    end
    table.sort(found)
    if #found == 0 then
        print("No monitor detected.")
    else
        for _, name in ipairs(found) do
            local mon = peripheral.wrap(name)
            local w, h = mon.getSize()
            print(string.format("%-16s %dx%d", name, w, h))
        end
    end
    return
end

if cmd == "views" then
    local s = display.status()
    if not s.views or #s.views == 0 then
        print("No selectable views published.")
    else
        for _, item in ipairs(s.views) do
            local marker = item.id == s.selectedView and "*" or " "
            print(marker .. " " .. item.id .. "  " .. item.label)
        end
    end
    return
end

if cmd == "select" then
    if not args[2] then error("view id required") end
    local ok, err = display.select(args[2])
    if not ok then error(err) end
    print("Selected display view: " .. tostring(args[2]))
    return
end

if cmd == "clear" then
    local ok, err = display.clear(args[2])
    if not ok then error(err) end
    print("Display publication cleared.")
    return
end

if cmd == "demo" then
    display.publish("displayctl", {
        title = "CC INFRA DISPLAY",
        subtitle = "display module API",
        lines = {
            "Display is driven by a published descriptor.",
            "Business modules can replace this view.",
            "Use displayctl clear to return to fallback.",
        },
    })
    print("Demo view published.")
    return
end

print("displayctl status")
print("displayctl detect")
print("displayctl use auto|<monitor>|off")
print("displayctl views")
print("displayctl select <view>")
print("displayctl demo")
print("displayctl clear [owner]")
