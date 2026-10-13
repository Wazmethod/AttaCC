local config = require("lib.config")
local machineInfo = require("lib.machine")
local runtime = require("lib.runtime")
local displayApi = require("lib.display_api")
local webcap = require("lib.webcap")

local machine = machineInfo.get()

local function profile()
    if type(config.standaloneDisplay) == "table" then return config.standaloneDisplay end
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

local function drawPublished(mon, descriptor, name)
    local p = profile()
    pcall(function()
        if mon.setGraphicsMode then mon.setGraphicsMode(false) end
    end)
    if mon.setTextScale then pcall(mon.setTextScale, tonumber(p.textScale) or 0.5) end

    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
    mon.setCursorPos(1, 1)

    local w, h = mon.getSize()
    local function line(s, color)
        if color then mon.setTextColor(color) end
        mon.write(tostring(s or ""):sub(1, w))
        mon.setTextColor(colors.white)
        local _, y = mon.getCursorPos()
        if y < h then mon.setCursorPos(1, y + 1) end
    end

    line(descriptor.title or "CC INFRA DISPLAY", colors.cyan)
    if descriptor.subtitle then line(descriptor.subtitle, colors.lime) end
    if descriptor.owner then line("[" .. tostring(descriptor.owner) .. "]", colors.gray) end
    if descriptor.lines then
        line("")
        for _, value in ipairs(descriptor.lines) do
            local text = type(value) == "table" and (value.text or value.label or "") or value
            line(text)
        end
    end
    return true
end

local function draw(mon, name)
    local published = displayApi.resolved()
    if published then return drawPublished(mon, published, name) end

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
local viewRows = {}

local function drawLocalStatus(detail)
    viewRows = {}
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)

    term.setTextColor(colors.cyan)
    print("CC INFRA DISPLAY")
    term.setTextColor(colors.gray)
    print("Host    : " .. tostring(machine.hostname or machine.key))
    print("Monitor : " .. tostring(currentName or "(none)"))
    term.setTextColor(detail == "active" and colors.lime or colors.orange)
    print("State   : " .. tostring(detail or "unknown"))

    local status = displayApi.status()
    term.setTextColor(colors.white)
    print("Owner   : " .. tostring(status.owner or "(fallback)"))
    print("View    : " .. tostring(status.selectedView or "(default)"))

    if #status.views > 0 then
        print("")
        term.setTextColor(colors.yellow)
        print("VIEWS FROM " .. tostring(status.owner))
        term.setTextColor(colors.white)
        for i, item in ipairs(status.views) do
            if i > 9 then break end
            local y = select(2, term.getCursorPos())
            local selected = item.id == status.selectedView
            term.setTextColor(selected and colors.lime or colors.white)
            print(string.format("[%d] %s%s", i, item.label, selected and "  <" or ""))
            viewRows[y] = item.id
        end
    else
        print("")
        term.setTextColor(colors.gray)
        print("No selectable views published by the business module.")
    end

    term.setTextColor(colors.lightGray)
    print("")
    print("1-9/click: select view   C: clear   R: refresh")
    term.setTextColor(colors.white)
end

local timer = os.startTimer(1)

while true do
    local mon, nameOrErr = resolve()
    if mon then
        currentName = nameOrErr
        local okDraw, drawErr = pcall(draw, mon, currentName)
        if okDraw then
            runtime.set("module:core.display", "active", {
                device = currentName,
                detail = "generic infrastructure display active",
            })
        else
            runtime.set("module:core.display", "degraded", {
                device = currentName,
                detail = tostring(drawErr),
            })
        end
    else
        currentName = nil
        runtime.set("module:core.display", "inactive", {
            detail = nameOrErr,
        })
    end

    local displayStatus = displayApi.status()
    local viewLabels = {}
    for _, item in ipairs(displayStatus.views or {}) do table.insert(viewLabels, item.label) end
    webcap.publish("display", {
        monitor = currentName,
        owner = displayStatus.owner or "fallback",
        view = displayStatus.selectedView or "default",
        views = viewLabels,
    })

    drawLocalStatus(mon and "active" or nameOrErr)

    local event, p1 = os.pullEvent()
    if event == "timer" and p1 == timer then
        timer = os.startTimer(1)
    elseif event == "peripheral" or event == "peripheral_detach" then
        timer = os.startTimer(0.05)
    elseif event == "key" then
        local numberKeys = {
            [keys.one] = 1, [keys.two] = 2, [keys.three] = 3,
            [keys.four] = 4, [keys.five] = 5, [keys.six] = 6,
            [keys.seven] = 7, [keys.eight] = 8, [keys.nine] = 9,
        }
        local index = numberKeys[p1]
        if index then
            local views = displayApi.views()
            if views[index] then displayApi.select(views[index].id) end
        elseif p1 == keys.c then
            displayApi.clear()
        elseif p1 == keys.r then
            -- redraw on next loop
        end
        timer = os.startTimer(0.05)
    elseif event == "mouse_click" then
        local id = viewRows[p3]
        if id then displayApi.select(id) end
        timer = os.startTimer(0.05)
    end
end
