local config = require("lib.config")
local protocol = require("lib.protocol")
local telemetry = require("lib.telemetry")
local controller = require("lib.controller")

local modem = protocol.findWirelessModem()
if not modem then error("Wireless modem introuvable") end

modem.open(config.channels.control)

controller.setEventSink(function(event)
    protocol.send(modem, config.channels.events, event)
end)

local function display(data)
    term.clear()
    term.setCursorPos(1, 1)

    print("=== STEAM PLANT COLLECTOR ===")
    print("Plant: " .. tostring(data.plant.status))
    print("Ctrl : " .. tostring(data.control.state))
    print("Armed: " .. tostring(data.control.armed))

    if data.control.error then
        print("Err: " .. tostring(data.control.error))
    end

    print("")
    print(string.format("RPM:     %.1f", data.power.rpm))
    print(string.format("Stress:  %.0f / %.0f SU",
        data.power.stress,
        data.power.capacity))
    print(string.format("Load:    %.1f%%", data.power.load))

    print("")
    print(string.format("Boiler:  Lvl %d", data.boiler.level))
    print(string.format("Water:   %.1f%%", data.boiler.water))
    print(string.format("Heat:    %.1f%%", data.boiler.heat))

    print("")
    print(string.format("Battery: %.1f%%", data.battery.percent))
    print(string.format("Motor:   %.1f RPM / %.0f FE/t",
        data.motor.rpm,
        data.motor.consumption))

    print("")
    print("MAIN: " .. (data.control.mainClutchEngaged and "ON" or "CUT"))
    print("GEN : " .. (data.control.genClutchEngaged and "ON" or "CUT"))
    print("ALT : " .. (data.control.alternatorClutchEngaged and "ON" or "CUT"))
end

local tickTimer = os.startTimer(config.timing.collectorTick)

while true do
    local event, p1, p2, p3, p4 = os.pullEvent()

    if event == "modem_message" then
        if p2 == config.channels.control then
            controller.handleCommand(modem, p4)
        end

    elseif event == "timer" and p1 == tickTimer then
        controller.update()

        -- Read every Create peripheral only ONCE per tick.
        local ok, data = pcall(telemetry.collect, controller)

        if ok then
            controller.updateDetection(data.power)

            -- Update only the cheap controller-derived fields after detection.
            data.control.state = controller.getState()
            data.control.error = controller.getError()
            data.control.automatic = controller.isAutomatic()
            data.control.armed = controller.isArmed()
            data.control.plantOffline = controller.isPlantOffline()

            -- Plant status will naturally be fully reflected on the next 0.5 s frame.
            protocol.send(modem, config.channels.telemetry, data)
            display(data)
        else
            term.clear()
            term.setCursorPos(1, 1)
            print("COLLECTOR ERROR")
            print(tostring(data))
        end

        tickTimer = os.startTimer(config.timing.collectorTick)
    end
end
