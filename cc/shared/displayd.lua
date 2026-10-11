local config = require("lib.config")
local machineInfo = require("lib.machine")
local runtime = require("lib.runtime")

local machine = machineInfo.get()

local function profile()
    if type(config.standaloneDisplay) == "table" then return config.standaloneDisplay end
    if machine.role == "workstation"
        and config.workstation and type(config.workstation.display) == "table"
    then
        return config.workstation.display
    end
    return { enabled = false }
end

local function hasType(name, expected)
    if not name or not peripheral.isPresent(name) then return false end
    local types = { peripheral.getType(name) }
    for _, t in ipairs(types) do if t == expected then return true end end
    return false
end

local function resolve()
    local p = profile()
    if p.enabled == false then return nil, "disabled by profile" end

    local configured = p.peripheral or p.monitor or p.monitorName
    if configured and configured ~= "" and configured ~= "auto" then
        if not peripheral.isPresent(configured) then
            return nil, "configured monitor missing: " .. tostring(configured)
        end
        if not hasType(configured, "monitor") then
            return nil, "configured peripheral is not a monitor: " .. tostring(configured)
        end
        return peripheral.wrap(configured), configured
    end

    local mon = peripheral.find("monitor")
    if not mon then return nil, "no monitor present" end
    return mon, peripheral.getName(mon)
end

local function draw(mon, name)
    local p = profile()
    pcall(function()
        if mon.setGraphicsMode then mon.setGraphicsMode(false) end
    end)
    if mon.setTextScale then pcall(mon.setTextScale, tonumber(p.textScale) or 0.5) end

    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
    mon.setCursorPos(1, 1)

    local w = select(1, mon.getSize())
    local function line(s, color)
        if color then mon.setTextColor(color) end
        mon.write(tostring(s):sub(1, w))
        mon.setTextColor(colors.white)
        local _, y = mon.getCursorPos()
        mon.setCursorPos(1, y + 1)
    end

    line("CC INFRA DISPLAY", colors.cyan)
    line(machine.hostname or machine.key, colors.lime)
    line(machine.networkLabel or machine.network)
    line("")
    line("Machine: " .. tostring(machine.key))
    line("Preset : " .. tostring(machine.preset or machine.role))
    line("Monitor: " .. tostring(name))
    line("")
    line("Modules:")
    local snap = runtime.snapshot()
    local seen = false
    for key, state in pairs(snap.services or {}) do
        local mod = key:match("^module:(.+)$")
        if mod then
            seen = true
            line(" " .. mod .. " [" .. tostring(state.status or "?") .. "]")
        end
    end
    if not seen then line(" (none reporting)") end
end

local currentName = nil
local timer = os.startTimer(1)

while true do
    local mon, nameOrErr = resolve()
    if mon then
        currentName = nameOrErr
        runtime.set("module:core.display", "active", {
            device = currentName,
            detail = "generic infrastructure display active",
        })
        pcall(draw, mon, currentName)
    else
        currentName = nil
        runtime.set("module:core.display", "inactive", {
            detail = nameOrErr,
        })
    end

    local event, p1 = os.pullEvent()
    if event == "timer" and p1 == timer then
        timer = os.startTimer(1)
    elseif event == "peripheral" or event == "peripheral_detach" then
        timer = os.startTimer(0.05)
    end
end
