local config = require("lib.config")
local protocol = require("lib.protocol")
local machineInfo = require("lib.machine")
local nodes = require("lib.nodes")
local runtime = require("lib.runtime")
local services = require("lib.services")

local modem = protocol.findWirelessModem()
if not modem then
    runtime.log("service:workstation", "error", "wireless modem unavailable")
    error("Wireless modem unavailable")
end

local machine = machineInfo.get("workstation")
local nodeBus = nodes.new(modem, "workstation")

services.syncRuntime()
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
        timer = os.startTimer(1)
    elseif event == "peripheral" or event == "peripheral_detach" then
        runtime.log("workstation", "info",
            event .. ": " .. tostring(p1))
    end
end
