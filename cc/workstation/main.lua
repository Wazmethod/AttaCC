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
        runtime.set("module:workstation.console", "active", {
            device = item.name,
            configured = item.configured,
            detail = item.expected .. " peripheral ready",
        })
    elseif item.enabled then
        runtime.set("module:workstation.console", "inactive", {
            configured = item.configured,
            detail = item.detail,
        })
    else
        runtime.set("module:workstation.console", "disabled", {
            detail = "disabled by profile",
        })
    end

    return status
end

local function redraw(status)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)

    print("CC Infrastructure Workstation")
    print("Hostname : " .. tostring(machine.hostname))
    print("Machine  : " .. tostring(machine.key))
    print("Network  : " .. tostring(machine.network))
    print("")

    local function line(label, item)
        local value
        if item.enabled and item.present then
            value = "ACTIVE  " .. tostring(item.name)
        elseif item.enabled then
            value = string.upper(tostring(item.state or "inactive"))
                .. "  " .. tostring(item.configured or "")
        else
            value = "DISABLED"
        end
        print(string.format("%-8s: %s", label, value))
    end

    line("Console", status.console)
    line("Display", status.display)
    print("")
    print("[C] console  [S] ssh scan  [N] storage ns")
    print("[D] display  [M] modules   [R] refresh")
end

services.syncRuntime()
runtime.remove("module:workstation.display")
runtime.set("module:client.workstation", "active", {
    detail = "interactive workstation runtime active",
})
local status = syncDevices()
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
        if p1 == keys.c and status.console and status.console.present then
            openTool("console.lua", "console")
        elseif p1 == keys.s then
            openTool("ssh.lua", "ssh-scan", "--scan")
        elseif p1 == keys.n then
            openTool("storagectl.lua", "storage-ns", "ns")
        elseif p1 == keys.d then
            openTool("displayctl.lua", "displayctl", "status")
        elseif p1 == keys.m then
            openTool("lsmod.lua", "lsmod")
        elseif p1 == keys.r then
            status = syncDevices()
        end
        redraw(status)
    end
end
