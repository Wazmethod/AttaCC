local config = require("lib.config")
local protocol = require("lib.protocol")
local machineInfo = require("lib.machine")
local nodes = require("lib.nodes")
local runtime = require("lib.runtime")
local services = require("lib.services")
local devices = require("lib.devices")

local modem = protocol.findWirelessModem()
if not modem then
    runtime.log("service:workstation", "error", "wireless modem unavailable")
    error("Wireless modem unavailable")
end

local machine = machineInfo.get("workstation")
local nodeBus = nodes.new(modem, "workstation")
local hitboxes = {}

local function openTool(path, title, ...)
    if not shell.openTab then return nil end
    local id = shell.openTab(path, ...)
    if title and multishell and multishell.setTitle then
        pcall(multishell.setTitle, id, title)
    end
    return id
end

local function syncDevices()
    local status = devices.all()

    local item = status.console
    if item.enabled and item.present then
        runtime.set("module:core.console", "active", {
            device = item.name,
            configured = item.configured,
            detail = item.expected .. " peripheral ready",
        })
    elseif item.enabled then
        runtime.set("module:core.console", "inactive", {
            configured = item.configured,
            detail = item.detail,
        })
    else
        runtime.set("module:core.console", "disabled", {
            detail = "disabled by profile",
        })
    end

    return status
end

local function button(x, y, label, key, action, enabled)
    enabled = enabled ~= false
    term.setCursorPos(x, y)
    term.setBackgroundColor(enabled and colors.gray or colors.black)
    term.setTextColor(enabled and colors.white or colors.lightGray)
    write(" " .. label .. " ")
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)

    table.insert(hitboxes, {
        x1 = x,
        x2 = x + #label + 1,
        y = y,
        key = key,
        action = action,
        enabled = enabled,
    })
end

local function statusLine(y, label, item)
    term.setCursorPos(2, y)
    term.setTextColor(colors.lightGray)
    write(string.format("%-8s ", label))

    if item.enabled and item.present then
        term.setTextColor(colors.lime)
        write("ACTIVE")
        term.setTextColor(colors.gray)
        write("  " .. tostring(item.name))
    elseif item.enabled then
        term.setTextColor(colors.orange)
        write(string.upper(tostring(item.state or "inactive")))
        term.setTextColor(colors.gray)
        write("  " .. tostring(item.configured or ""))
    else
        term.setTextColor(colors.gray)
        write("DISABLED")
    end
    term.setTextColor(colors.white)
end

local function redraw(status)
    hitboxes = {}
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()

    local w = select(1, term.getSize())

    term.setCursorPos(2, 1)
    term.setTextColor(colors.cyan)
    write("CC INFRA WORKSTATION")
    term.setTextColor(colors.gray)
    local owner = "client.workstation.mod"
    if w > 50 then
        term.setCursorPos(math.max(2, w - #owner), 1)
        write(owner)
    end

    term.setCursorPos(2, 3)
    term.setTextColor(colors.white)
    write(tostring(machine.hostname))
    term.setTextColor(colors.gray)
    write("  " .. tostring(machine.network))

    statusLine(5, "Console", status.console)
    statusLine(6, "Display", status.display)

    term.setCursorPos(2, 8)
    term.setTextColor(colors.yellow)
    write("TOOLS")
    term.setTextColor(colors.white)

    button(2, 10, "Console", keys.c, "console", status.console and status.console.present)
    button(14, 10, "SSH scan", keys.s, "ssh")
    button(28, 10, "Storage", keys.n, "storage")
    button(41, 10, "Display", keys.d, "display")
    button(54, 10, "Modules", keys.m, "modules")
    button(67, 10, "Refresh", keys.r, "refresh")

    term.setCursorPos(2, 12)
    term.setTextColor(colors.gray)
    write("Keyboard: C/S/N/D/M/R  |  mouse: click a button")
    term.setTextColor(colors.white)
end

local status = syncDevices()

local function runAction(action)
    if action == "console" then
        if status.console and status.console.present then openTool("console.lua", "console") end
    elseif action == "ssh" then
        openTool("ssh.lua", "ssh-scan", "--scan")
    elseif action == "storage" then
        openTool("storagectl.lua", "storage-ns", "ns")
    elseif action == "display" then
        openTool("displayctl.lua", "displayctl", "status")
    elseif action == "modules" then
        openTool("lsmod.lua", "lsmod")
    elseif action == "refresh" then
        status = syncDevices()
    end
end

local function keyAction(key)
    for _, h in ipairs(hitboxes) do
        if h.key == key and h.enabled then
            runAction(h.action)
            return
        end
    end
end

local function mouseAction(x, y)
    for _, h in ipairs(hitboxes) do
        if h.enabled and y == h.y and x >= h.x1 and x <= h.x2 then
            runAction(h.action)
            return
        end
    end
end

services.syncRuntime()
runtime.remove("module:workstation.display")
runtime.set("module:client.workstation", "active", {
    detail = "interactive workstation control panel active",
})
redraw(status)
runtime.log("service:workstation", "info",
    "interactive workstation online as " .. tostring(machine.hostname))

local timer = os.startTimer(1)

while true do
    local event, p1, p2, p3, p4 = os.pullEvent()

    if event == "modem_message" then
        local action = nodeBus:handle(p2, p4)
        if action == "reboot" then
            sleep(0.15)
            os.reboot()
        end

    elseif event == "timer" and p1 == timer then
        if services.isActive("network") then nodeBus:tick() end
        services.syncRuntime()
        status = syncDevices()
        redraw(status)
        timer = os.startTimer(1)

    elseif event == "peripheral" or event == "peripheral_detach" then
        runtime.log("workstation", "info", event .. ": " .. tostring(p1))
        status = syncDevices()
        redraw(status)

    elseif event == "key" then
        keyAction(p1)
        redraw(status)

    elseif event == "mouse_click" then
        mouseAction(p2, p3)
        redraw(status)
    end
end
