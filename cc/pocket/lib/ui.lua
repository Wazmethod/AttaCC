local M = {}

M.pageCount = 4

local function wh()
    return term.getSize()
end

local function put(x, y, s, fg, bg)
    if y < 1 or y > select(2, wh()) then return end
    term.setCursorPos(x, y)
    if bg then term.setBackgroundColor(bg) end
    term.setTextColor(fg or colors.white)
    term.write(s)
    if bg then term.setBackgroundColor(colors.black) end
end

local function fill(x, y, width, bg)
    if width <= 0 then return end
    term.setCursorPos(x, y)
    term.setBackgroundColor(bg)
    term.write(string.rep(" ", width))
    term.setBackgroundColor(colors.black)
end

local function button(y, label, bg, fg)
    local w = wh()
    fill(1, y, w, bg)
    local x = math.max(1, math.floor((w - #label) / 2) + 1)
    put(x, y, label, fg or colors.white, bg)
end

local function bar(y, label, value, color)
    local w = wh()
    local pct = math.max(0, math.min(100, value or 0))
    local val = string.format("%3.0f%%", pct)
    local start = #label + 2
    local width = math.max(3, w - start - #val)
    local n = math.floor(width * pct / 100 + 0.5)

    put(1, y, label, colors.white)
    if n > 0 then fill(start, y, n, color) end
    if width - n > 0 then fill(start + n, y, width - n, colors.gray) end
    put(start + width + 1, y, val, colors.white)
end

local function header(page, masterAlive, collectorFresh, pending)
    local w = wh()
    put(1, 1, "STEAM", colors.cyan)

    local p = tostring(page) .. "/" .. tostring(M.pageCount)
    put(math.max(1, w - #p - 2), 1, p, colors.lightGray)

    local c =
        pending and colors.orange
        or (not masterAlive and colors.red)
        or (collectorFresh and colors.lime or colors.orange)

    term.setCursorPos(w, 1)
    term.setBackgroundColor(c)
    term.write(" ")
    term.setBackgroundColor(colors.black)
end

local function statusPage(data, collectorFresh)
    local state = data and data.plant and data.plant.status or "NO DATA"
    local bg =
        (state == "RUNNING" or state == "ONLINE") and colors.green
        or state == "STARTING" and colors.orange
        or state == "DEGRADED" and colors.orange
        or colors.red

    button(3, collectorFresh and state or "DATA STALE", collectorFresh and bg or colors.red)

    if not data then
        put(1, 5, "No collector data", colors.red)
        return
    end

    put(1, 5, string.format("RPM %6.1f", data.power.rpm))
    put(13, 5, string.format("L %4.1f%%", data.power.load))

    put(1, 7, "BOILER", colors.yellow)
    bar(8, "W", data.boiler.water, colors.blue)
    bar(9, "H", data.boiler.heat, colors.red)

    put(1, 11, "BATTERY", colors.yellow)
    bar(12, "B", data.battery.percent,
        data.battery.percent < 15 and colors.red
        or data.battery.percent < 35 and colors.orange
        or colors.lime)

    put(1, 14, "CTRL " .. tostring(data.control.state), colors.lightGray)
    put(1, 15, "AUTO " .. (data.control.armed and "ARMED" or "DISARMED"),
        data.control.armed and colors.lime or colors.red)

    button(17, "AUTO START", colors.green)
    button(18, "ABORT", colors.red)
end

local function clutchPage(data)
    if not data then
        put(1, 4, "No collector data", colors.red)
        return
    end

    put(1, 3, "CLUTCH CONTROL", colors.yellow)

    put(1, 5, "MAIN")
    button(6, data.control.mainClutchEngaged and "ENGAGED" or "CUT",
        data.control.mainClutchEngaged and colors.green or colors.red)

    put(1, 8, "GENERATOR")
    button(9, data.control.genClutchEngaged and "ENGAGED" or "CUT",
        data.control.genClutchEngaged and colors.green or colors.red)

    put(1, 11, "ALTERNATOR")
    button(12, data.control.alternatorClutchEngaged and "ENGAGED" or "CUT",
        data.control.alternatorClutchEngaged and colors.green or colors.red)

    button(15, "ALL CUT", colors.orange, colors.black)
    button(17, "RUN TOPOLOGY", colors.blue)
end

local function motorPage(data)
    if not data then
        put(1, 4, "No collector data", colors.red)
        return
    end

    local w = wh()
    put(1, 3, "ELECTRIC MOTOR", colors.yellow)
    put(1, 5, string.format("RPM   %7.1f", data.motor.rpm))
    put(1, 6, string.format("DRAW  %7.0f FE/t", data.motor.consumption))

    put(1, 8, "BATTERY", colors.yellow)
    bar(9, "B", data.battery.percent, colors.lime)

    local lw = math.floor((w - 1) / 2)
    local rx = lw + 2
    local rw = w - rx + 1

    fill(1, 12, lw, colors.blue)
    put(math.max(1, math.floor((lw - 6) / 2) + 1), 12, "32 RPM", colors.white, colors.blue)
    fill(rx, 12, rw, colors.blue)
    put(rx + math.max(0, math.floor((rw - 6) / 2)), 12, "64 RPM", colors.white, colors.blue)

    fill(1, 14, lw, colors.cyan)
    put(math.max(1, math.floor((lw - 7) / 2) + 1), 14, "128 RPM", colors.black, colors.cyan)
    fill(rx, 14, rw, colors.red)
    put(rx + math.max(0, math.floor((rw - 4) / 2)), 14, "STOP", colors.white, colors.red)
end

local function eventsPage(events)
    local w = wh()
    put(1, 3, "EVENTS", colors.yellow)

    if not events or #events == 0 then
        put(1, 5, "No events", colors.lightGray)
        return
    end

    for i = 1, math.min(#events, 15) do
        local e = events[i]
        local c =
            e.level == "critical" and colors.red
            or e.level == "warning" and colors.orange
            or e.level == "success" and colors.lime
            or colors.lightBlue

        put(1, 3 + i, tostring(e.message or e.code or "event"):sub(1, w), c)
    end
end

local function footer(page)
    local w, h = wh()
    local names = {"STATUS", "CLUTCH", "MOTOR", "EVENTS"}
    local s = names[page]
    put(math.max(1, math.floor((w - #s) / 2) + 1), h, s, colors.gray)
    if page > 1 then put(1, h, "<", colors.lightGray) end
    if page < M.pageCount then put(w, h, ">", colors.lightGray) end
end

function M.draw(page, data, events, masterAlive, collectorFresh, pending, toast, toastColor)
    term.setBackgroundColor(colors.black)
    term.clear()

    header(page, masterAlive, collectorFresh, pending)

    if page == 1 then
        statusPage(data, collectorFresh)
    elseif page == 2 then
        clutchPage(data)
    elseif page == 3 then
        motorPage(data)
    else
        eventsPage(events)
    end

    local w, h = wh()
    if toast then
        put(1, h - 1, toast:sub(1, w), toastColor or colors.white)
    end
    footer(page)
end

function M.click(page, data, x, y)
    if not data then return nil end
    local w = wh()

    if page == 1 then
        if y == 17 then return "procedure"
        elseif y == 18 then return "abort"
        elseif y == 15 then return data.control.armed and "disarm" or "arm" end

    elseif page == 2 then
        if y == 6 then return data.control.mainClutchEngaged and "main_off" or "main_on"
        elseif y == 9 then return data.control.genClutchEngaged and "gen_off" or "gen_on"
        elseif y == 12 then return data.control.alternatorClutchEngaged and "alt_off" or "alt_on"
        elseif y == 15 then return "all_cut"
        elseif y == 17 then return "running_topology" end

    elseif page == 3 then
        local lw = math.floor((w - 1) / 2)
        local rx = lw + 2
        if y == 12 then
            if x <= lw then return "motor_speed", 32 end
            if x >= rx then return "motor_speed", 64 end
        elseif y == 14 then
            if x <= lw then return "motor_speed", 128 end
            if x >= rx then return "motor_stop" end
        end
    end

    return nil
end

return M
