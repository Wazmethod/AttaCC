local config = require("lib.config")
local controller = require("lib.controller")
local telemetry = require("lib.telemetry")

local M = {
    id = "steamplant",
    displayDriver = "steamplant",
}

function M.init(ctx)
    controller.setEventSink(function(event)
        ctx.emit(M.id, event.level, event.code, event.message, event)
    end)

    local ok, err = controller.prepareBootOutputs()
    if ok == false then
        return false, err
    end
    return true
end

function M.handleCommand(message, ctx)
    controller.handleCommand(ctx.modem, message)
    return true
end

function M.collect(ctx)
    local data = telemetry.collect(controller)

    if not controller.isInitialized() then
        controller.initialize(data.power)
    end

    controller.updateDetection(data.power)
    controller.update()

    data.control.state = controller.getState()
    data.control.error = controller.getError()
    data.control.automatic = controller.isAutomatic()
    data.control.armed = controller.isArmed()
    data.control.plantOffline = controller.isPlantOffline()

    data.network = ctx.machine.network
    data.module = M.id
    data.machine = ctx.machine.key

    data.ui = {
        kind = "controller",
        title = "Steam Engine",
        subtitle = "Steam plant controller",
        state = tostring(data.control.state or "UNKNOWN"),
        status = data.control.error and "failed"
            or (data.control.plantOffline and "warning" or "active"),
        metrics = {
            { label = "RPM", value = string.format("%.1f", data.power.rpm or 0), unit = "rpm" },
            { label = "LOAD", value = string.format("%.1f", data.power.load or 0), unit = "%" },
            { label = "WATER", value = string.format("%.0f", data.boiler.water or 0), unit = "%" },
            { label = "BATTERY", value = string.format("%.1f", data.battery.percent or 0), unit = "%" },
        },
        controls = {
            { command = "procedure", label = "AUTO START", tone = "good" },
            { command = data.control.armed and "disarm" or "arm",
              label = data.control.armed and "DISARM" or "ARM",
              tone = data.control.armed and "warn" or "good" },

            { command = data.control.mainClutchEngaged and "main_off" or "main_on",
              label = "MAIN " .. (data.control.mainClutchEngaged and "CUT" or "ON"),
              tone = data.control.mainClutchEngaged and "warn" or "good" },

            { command = data.control.alternatorClutchEngaged and "alt_off" or "alt_on",
              label = "ALT " .. (data.control.alternatorClutchEngaged and "CUT" or "ON"),
              tone = data.control.alternatorClutchEngaged and "warn" or "good" },

            { command = data.control.genClutchEngaged and "gen_off" or "gen_on",
              label = "GEN " .. (data.control.genClutchEngaged and "CUT" or "ON"),
              tone = data.control.genClutchEngaged and "warn" or "good" },

            { command = "abort", label = "ABORT", tone = "bad", confirm = true },
            { command = "motor_32", label = "32 RPM", tone = "blue" },
            { command = "motor_64", label = "64 RPM", tone = "blue" },
            { command = "motor_128", label = "128 RPM", tone = "blue" },
            { command = "motor_stop", label = "MOTOR STOP", tone = "bad" },
            { command = "running_topology", label = "RUN TOPOLOGY", tone = "blue", confirm = true },
        },
    }

    return data
end

function M.getDebug()
    return controller.getDebug()
end

return M
