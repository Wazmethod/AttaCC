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
    return data
end

function M.getDebug()
    return controller.getDebug()
end

return M
