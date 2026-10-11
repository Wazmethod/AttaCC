local M = {}
local hitboxes = {}
local function resetHits()
    hitboxes = {}
end
local function addHit(x1, y1, x2, y2, action, arg)
    table.insert(hitboxes, { x1=x1, y1=y1, x2=x2, y2=y2, action=action, arg=arg })
end
local function writeAt(mon, x, y, text, fg, bg)
    local w, h = mon.getSize()
    if y < 1 or y > h or x > w then return end
    text = tostring(text or "")
    if x < 1 then x = 1 end
    if #text > (w - x + 1) then text = text:sub(1, w - x + 1) end
    mon.setCursorPos(x, y)
    if bg then mon.setBackgroundColor(bg) end
    mon.setTextColor(fg or colors.white)
    mon.write(text)
    if bg then mon.setBackgroundColor(colors.black) end
end
local function fill(mon, x, y, width, bg)
    local w, h = mon.getSize()
    if y < 1 or y > h or x > w or width < 1 then return end
    width = math.min(width, w - x + 1)
    mon.setCursorPos(x, y)
    mon.setBackgroundColor(bg)
    mon.write(string.rep(" ", width))
    mon.setBackgroundColor(colors.black)
end
local function centerIn(mon, x, y, width, text, fg, bg)
    fill(mon, x, y, width, bg)
    local tx = x + math.max(0, math.floor((width - #text) / 2))
    writeAt(mon, tx, y, text, fg or colors.white, bg)
end
local function bar(mon, x, y, width, value, fg)
    value = math.max(0, math.min(100, value or 0))
    local filled = math.floor(width * value / 100 + 0.5)
    if filled > 0 then fill(mon, x, y, filled, fg) end
    if width - filled > 0 then fill(mon, x + filled, y, width - filled, colors.gray) end
end
local function statusColor(status)
    if status == "RUNNING" or status == "ONLINE" then return colors.green end
    if status == "STARTING" or status == "DEGRADED" then return colors.orange end
    return colors.red
end
local function button(mon, x, y, width, label, bg, action, arg)
    centerIn(mon, x, y, width, label, colors.white, bg)
    addHit(x, y, x + width - 1, y, action, arg)
end
local function levelColor(level)
    if level == "critical" then return colors.red end
    if level == "warning" then return colors.orange end
    if level == "success" then return colors.lime end
    return colors.lightBlue
end
local function fmtAge(ms)
    if not ms then return "-" end
    if ms < 1000 then return tostring(math.floor(ms)) .. "ms" end
    return string.format("%.1fs", ms / 1000)
end
local function fmtTime(ms)
    if not ms then return "--:--:--" end
    local sec = math.floor(ms / 1000)
    local h = math.floor((sec / 3600) % 24)
    local m = math.floor((sec / 60) % 60)
    local s = sec % 60
    return string.format("%02d:%02d:%02d", h, m, s)
end
local function drawHeader(mon, page, data)
    local w = select(1, mon.getSize())
    fill(mon, 1, 1, w, colors.gray)
    writeAt(mon, 2, 1, "LOCAL COLLECTOR", colors.white, colors.gray)
    local title = page == "debug" and "DEBUG" or "DASHBOARD"
    writeAt(mon, math.max(15, math.floor((w - #title) / 2)), 1, title, colors.yellow, colors.gray)
    if data then
        local status = data.plant and data.plant.status or "NO DATA"
        local statusText = " " .. status .. " "
        writeAt(mon, math.max(2, w - #statusText - 1), 1, statusText, colors.white, statusColor(status))
    end
end
local function drawDashboard(mon, data, collectorFresh, latestEvent, pending)
    local w, h = mon.getSize()
    drawHeader(mon, "dashboard", data)
    local sideW = math.min(20, math.max(16, math.floor(w * 0.28)))
    local sideX = w - sideW + 1
    local mainW = sideX - 2
    writeAt(mon, sideX + 1, 3, "CONTROL", colors.yellow)
    if not data then
        writeAt(mon, 2, 4, "Waiting for collector telemetry...", colors.orange)
        button(mon, sideX + 1, h - 1, sideW - 2, "DEBUG", colors.blue, "page", "debug")
        return
    end
    writeAt(mon, 2, 3, "POWER", colors.yellow)
    writeAt(mon, 2, 5, string.format("RPM %7.1f", data.power.rpm))
    writeAt(mon, 16, 5, string.format("LOAD %5.1f%%", data.power.load))
    writeAt(mon, 2, 6, string.format("STRESS %.0f / %.0f SU", data.power.stress, data.power.capacity), colors.lightGray)
    writeAt(mon, 2, 8, "BOILER", colors.yellow)
    writeAt(mon, 2, 9, "WATER")
    bar(mon, 10, 9, math.max(8, mainW - 18), data.boiler.water, colors.blue)
    writeAt(mon, math.max(12, mainW - 6), 9, string.format("%3.0f%%", data.boiler.water))
    writeAt(mon, 2, 10, "HEAT")
    bar(mon, 10, 10, math.max(8, mainW - 18), data.boiler.heat, colors.red)
    writeAt(mon, math.max(12, mainW - 6), 10, string.format("%3.0f%%", data.boiler.heat))
    writeAt(mon, 2, 12, "BATTERY", colors.yellow)
    bar(mon, 2, 13, math.max(10, mainW - 10), data.battery.percent,
        data.battery.percent < 15 and colors.red or data.battery.percent < 35 and colors.orange or colors.lime)
    writeAt(mon, math.max(12, mainW - 7), 13, string.format("%5.1f%%", data.battery.percent))
    writeAt(mon, 2, 15, "CLUTCHES", colors.yellow)
    centerIn(mon, 2, 16, 10, "MAIN", colors.white, data.control.mainClutchEngaged and colors.green or colors.red)
    centerIn(mon, 14, 16, 10, "GEN", colors.white, data.control.genClutchEngaged and colors.green or colors.red)
    centerIn(mon, 26, 16, 10, "ALT", colors.white, data.control.alternatorClutchEngaged and colors.green or colors.red)
    writeAt(mon, 2, 18, "CTRL " .. tostring(data.control.state), colors.lightGray)
    writeAt(mon, 2, 19, "AUTO " .. (data.control.armed and "ARMED" or "DISARMED"), data.control.armed and colors.lime or colors.red)
    if not collectorFresh then
        centerIn(mon, 2, 21, math.max(12, mainW - 2), "TELEMETRY STALE", colors.white, colors.red)
    elseif latestEvent then
        writeAt(mon, 2, 21, ("EVENT " .. tostring(latestEvent.message)):sub(1, math.max(1, mainW - 2)), levelColor(latestEvent.level))
    end
    local bw = sideW - 2
    local bx = sideX + 1
    button(mon, bx, 5, bw, "AUTO START", colors.green, "command", "procedure")
    button(mon, bx, 7, bw, "ABORT", colors.red, "command", "abort")
    button(mon, bx, 9, bw, data.control.armed and "DISARM" or "ARM",
        data.control.armed and colors.orange or colors.green, "command", data.control.armed and "disarm" or "arm")
    button(mon, bx, 12, bw, "MAIN " .. (data.control.mainClutchEngaged and "ON" or "CUT"),
        data.control.mainClutchEngaged and colors.green or colors.red, "command", data.control.mainClutchEngaged and "main_off" or "main_on")
    button(mon, bx, 14, bw, "GEN " .. (data.control.genClutchEngaged and "ON" or "CUT"),
        data.control.genClutchEngaged and colors.green or colors.red, "command", data.control.genClutchEngaged and "gen_off" or "gen_on")
    button(mon, bx, 16, bw, "ALT " .. (data.control.alternatorClutchEngaged and "ON" or "CUT"),
        data.control.alternatorClutchEngaged and colors.green or colors.red, "command", data.control.alternatorClutchEngaged and "alt_off" or "alt_on")
    button(mon, bx, 19, bw, "MOTOR STOP", colors.red, "command", "motor_stop")
    if h >= 22 then button(mon, bx, 21, bw, "RUN TOPOLOGY", colors.blue, "command", "running_topology") end
    button(mon, bx, h - 1, bw, "DEBUG", colors.purple, "page", "debug")
    -- Keep link state at the top of the control rail so it cannot collide
    -- with bottom actions such as telemetry resync/debug controls.
    writeAt(mon, bx, 4, collectorFresh and "LOCAL OK" or "LOCAL LOST",
        collectorFresh and colors.lime or colors.red)
    if pending then writeAt(mon, bx, math.max(2, h - 2), "CMD WAIT ACK", colors.orange) end
end
local function drawDebug(mon, data, collectorFresh, events, pending, debugInfo)
    local w, h = mon.getSize()
    drawHeader(mon, "debug", data)
    local rightX = math.max(30, math.floor(w * 0.50)) + 2
    writeAt(mon, 2, 3, "LINK / TIMING", colors.yellow)
    writeAt(mon, 2, 5, "Collector link : " .. (collectorFresh and "OK" or "STALE"), collectorFresh and colors.lime or colors.red)
    writeAt(mon, 2, 6, "Telemetry age : " .. fmtAge(debugInfo.telemetryAgeMs))
    writeAt(mon, 2, 7, "Last RX       : " .. fmtTime(debugInfo.lastTelemetry))
    writeAt(mon, 2, 8, "Master time   : " .. fmtTime(debugInfo.now))
    writeAt(mon, 2, 10, "COMMAND", colors.yellow)
    if pending then
        writeAt(mon, 2, 12, "Pending : " .. tostring(pending.command), colors.orange)
        writeAt(mon, 2, 13, "Retries : " .. tostring(pending.retries))
        writeAt(mon, 2, 14, "Age     : " .. fmtAge(debugInfo.now - (pending.sentAt or debugInfo.now)))
    else
        writeAt(mon, 2, 12, "Pending : none", colors.lime)
    end
    if data then
        writeAt(mon, 2, 16, "CONTROLLER", colors.yellow)
        writeAt(mon, 2, 18, "Plant : " .. tostring(data.plant and data.plant.status or "-"))
        writeAt(mon, 2, 19, "State : " .. tostring(data.control.state))
        writeAt(mon, 2, 20, "Armed : " .. tostring(data.control.armed))
        writeAt(mon, 2, 21, "Offln : " .. tostring(data.control.plantOffline))
        writeAt(mon, 2, 22, "Auto  : " .. tostring(data.control.automatic))
        if data.control.error then
            writeAt(mon, 2, 24, "ERROR:", colors.red)
            writeAt(mon, 2, 25, tostring(data.control.error), colors.red)
        end
        writeAt(mon, rightX, 3, "PHYSICAL", colors.yellow)
        writeAt(mon, rightX, 5, string.format("RPM       : %.2f", data.power.rpm))
        writeAt(mon, rightX, 6, string.format("Capacity  : %.0f SU", data.power.capacity))
        writeAt(mon, rightX, 7, string.format("Stress    : %.0f SU", data.power.stress))
        writeAt(mon, rightX, 8, string.format("Load      : %.1f%%", data.power.load))
        writeAt(mon, rightX, 10, string.format("Water     : %.1f%%", data.boiler.water))
        writeAt(mon, rightX, 11, string.format("Heat      : %.1f%%", data.boiler.heat))
        writeAt(mon, rightX, 12, string.format("Battery   : %.1f%%", data.battery.percent))
        writeAt(mon, rightX, 13, string.format("Motor RPM : %.1f", data.motor.rpm))
        writeAt(mon, rightX, 15, "MAIN : " .. tostring(data.control.mainClutchEngaged))
        writeAt(mon, rightX, 16, "GEN  : " .. tostring(data.control.genClutchEngaged))
        writeAt(mon, rightX, 17, "ALT  : " .. tostring(data.control.alternatorClutchEngaged))
    end
    local eventY = 27
    if h >= eventY + 2 then
        writeAt(mon, 2, eventY, "EVENT LOG", colors.yellow)
        local maxRows = h - eventY - 2
        for i = 1, math.min(#events, maxRows) do
            local e = events[i]
            writeAt(mon, 2, eventY + i, fmtTime(e.timestamp) .. " " .. tostring(e.code or "") .. " " .. tostring(e.message or ""), levelColor(e.level))
        end
    end
    button(mon, math.max(2, w - 18), h - 1, 16, "DASHBOARD", colors.blue, "page", "dashboard")
end
function M.draw(mon, page, data, collectorFresh, latestEvent, events, pending, debugInfo)
    resetHits()

    -- Always clear the full monitor before drawing a page. Without this,
    -- dashboard/debug elements from the previous frame remain visible.
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
    mon.setCursorPos(1, 1)
    if page == "debug" then
        drawDebug(mon, data, collectorFresh, events or {}, pending, debugInfo or {})
    else
        drawDashboard(mon, data, collectorFresh, latestEvent, pending)
    end
end
function M.actionAt(x, y)
    for _, h in ipairs(hitboxes) do
        if x >= h.x1 and x <= h.x2 and y >= h.y1 and y <= h.y2 then return h.action, h.arg end
    end
    return nil
end
return M
