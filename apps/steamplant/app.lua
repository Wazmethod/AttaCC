local config = require("lib.config")
local controller = require("lib.controller")
local telemetry = require("lib.telemetry")
local sdkAdapter = require("lib.steamplant_sdk")

local M = {
    id = "steamplant",
    displayDriver = "steamplant",
}

function M.init(ctx)
    controller.setEventSink(function(event)
        ctx.emit(M.id, event.level, event.code, event.message, event)
    end)

    local sdkApp = sdkAdapter.get()
    local declared, declarationError = sdkApp:registerIO()
    if not declared then return false, declarationError end

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

    sdkAdapter.update(data)
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
        app = {
            id = "steamplant",
            title = "SteamPlant Generator",
            machine = ctx.machine.key,
            machineLabel = ctx.machine.label or ctx.machine.hostname or ctx.machine.key,
            module = M.id,
            kind = "machine",
        },
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
        categories = {
            data = {
                { id = "steamplant", title = "SteamPlant", order = 1 },
                { id = "motor", title = "Motor", order = 2 },
                { id = "power", title = "Power", order = 3 },
            },
            graphs = {
                { id = "generator", title = "Generator", order = 1 },
                { id = "output", title = "Output", order = 2 },
                { id = "input", title = "Input", order = 3 },
            },
            controls = {
                { id = "start", title = "Start", order = 1 },
                { id = "clutches", title = "Clutches", order = 2 },
                { id = "starter", title = "Starter Motor", order = 3 },
            },
        },

        graphs = {
            { id = "rpm", group = "output", label = "RPM", value = tonumber(data.power.rpm) or 0, unit = "rpm",
              min = 0, max = 256, margin = 8, color = "cyan", gridX = 6, gridY = 4 },
            { id = "load", group = "output", label = "LOAD", value = tonumber(data.power.load) or 0, unit = "%",
              min = 0, max = 100, margin = 5, color = "orange", gridX = 6, gridY = 5 },
            { id = "battery", group = "generator", label = "BATTERY", value = tonumber(data.battery.percent) or 0, unit = "%",
              min = 0, max = 100, margin = 5, color = "lime", gridX = 6, gridY = 5 },
            { id = "water", group = "input", label = "WATER", value = tonumber(data.boiler.water) or 0, unit = "%",
              min = 0, max = 100, margin = 5, color = "blue", gridX = 6, gridY = 5 },
            { id = "heat", group = "input", label = "HEAT", value = tonumber(data.boiler.heat) or 0, unit = "%",
              min = 0, max = 100, margin = 5, color = "red", gridX = 6, gridY = 5 },
            { id = "motor_rpm", group = "generator", label = "MOTOR RPM", value = tonumber(data.motor.rpm) or 0, unit = "rpm",
              min = 0, max = 256, margin = 8, color = "yellow", gridX = 6, gridY = 4 },
        },

        controls = {
            { command = "procedure", label = "AUTO START", tone = "good", group = "start" },
            { command = data.control.armed and "disarm" or "arm",
              label = data.control.armed and "DISARM" or "ARM",
              tone = data.control.armed and "warn" or "good", group = "start" },

            { command = data.control.mainClutchEngaged and "main_off" or "main_on",
              label = "MAIN " .. (data.control.mainClutchEngaged and "ON" or "CUT"),
              tone = data.control.mainClutchEngaged and "good" or "warn", group = "clutches" },

            { command = data.control.alternatorClutchEngaged and "alt_off" or "alt_on",
              label = "ALT " .. (data.control.alternatorClutchEngaged and "ON" or "CUT"),
              tone = data.control.alternatorClutchEngaged and "good" or "warn", group = "clutches" },

            { command = data.control.genClutchEngaged and "gen_off" or "gen_on",
              label = "GEN " .. (data.control.genClutchEngaged and "ON" or "CUT"),
              tone = data.control.genClutchEngaged and "good" or "warn", group = "clutches" },

            { command = "abort", label = "ABORT", tone = "bad", confirm = true, group = "start" },
            { command = "motor_32", label = "32 RPM", tone = "blue", group = "starter" },
            { command = "motor_64", label = "64 RPM", tone = "blue", group = "starter" },
            { command = "motor_128", label = "128 RPM", tone = "blue", group = "starter" },
            { command = "motor_stop", label = "MOTOR STOP", tone = "bad", group = "starter" },

        },

        groups = {
            {
                id = "steamplant",
                title = "SteamPlant",
                metrics = {
                    { label = "STATE", value = tostring(data.plant.status or "UNKNOWN") },
                    { label = "WATER", value = string.format("%.0f", data.boiler.water or 0), unit = "%" },
                    { label = "HEAT", value = string.format("%.0f", data.boiler.heat or 0), unit = "%" },
                    { label = "AUTO", value = data.control.armed and "ARMED" or "DISARMED" },
                },
            },
            {
                id = "motor",
                title = "Motor",
                metrics = {
                    { label = "RPM", value = string.format("%.1f", data.motor.rpm or 0), unit = "rpm" },
                    { label = "DRAW", value = string.format("%.0f", data.motor.consumption or 0), unit = "FE/t" },
                },
            },
            {
                id = "power",
                title = "Power",
                metrics = {
                    { label = "RPM", value = string.format("%.1f", data.power.rpm or 0), unit = "rpm" },
                    { label = "LOAD", value = string.format("%.1f", data.power.load or 0), unit = "%" },
                    { label = "STRESS", value = string.format("%.0f", data.power.stress or 0), unit = "SU" },
                    { label = "CAPACITY", value = string.format("%.0f", data.power.capacity or 0), unit = "SU" },
                    { label = "BATTERY", value = string.format("%.1f", data.battery.percent or 0), unit = "%" },
                },
            },
        },
    }

    return data
end

function M.getDebug()
    return controller.getDebug()
end

return M
