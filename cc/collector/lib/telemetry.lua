local io = require("lib.io")
local protocol = require("lib.protocol")
local config = require("lib.config")

local M = {}

local function parseBar(line, label)
    if not line then return 0 end

    local bar = line:match("^%s*" .. label .. "%s+(.+)$")
    if not bar then return 0 end

    local filled, empty = 0, 0

    for i = 1, #bar do
        local b = string.byte(bar, i)
        if b == 127 then
            empty = empty + 1
        elseif b ~= 32 then
            filled = filled + 1
        end
    end

    local total = filled + empty
    if total == 0 then return 0 end
    return filled / total * 100
end

local function physicalState(controller, rpm, capacity)
    local absRpm = math.abs(rpm or 0)
    local cap = capacity or 0

    -- Physical telemetry wins over the controller state:
    -- as soon as the plant has real rotation/capacity, display RUNNING in green,
    -- even if the automatic startup sequence is still finishing its transfer.
    if absRpm >= config.detection.onlineRpm
        and cap >= config.detection.onlineCapacity
    then
        return "RUNNING"
    end

    local ctrl = controller.getState()

    if ctrl == "AUTO_WAIT_RPM"
        or ctrl == "AUTO_TRANSFER"
        or ctrl == "AUTO_VERIFY"
    then
        return "STARTING"
    end

    if ctrl == "AUTO_RETRY_WAIT" then
        return "OFFLINE"
    end

    if controller.isPlantOffline() then
        return "OFFLINE"
    end

    if absRpm <= config.detection.offlineRpm
        and cap <= config.detection.offlineCapacity
    then
        return "STOPPED"
    end

    return "DEGRADED"
end

function M.collect(controller)
    local l1 = io.target.getLine(1) or ""
    local l2 = io.target.getLine(2) or ""
    local l3 = io.target.getLine(3) or ""
    local l4 = io.target.getLine(4) or ""

    local rpm = io.speedometer.getSpeed() or 0
    local stress = io.stressometer.getStress() or 0
    local capacity = io.stressometer.getStressCapacity() or 0

    local energy = io.accumulator.getEnergy() or 0
    local energyCapacity = io.accumulator.getCapacity() or 0

    return {
        source = "steam_plant",
        timestamp = protocol.now(),

        plant = {
            status = physicalState(controller, rpm, capacity),
        },

        power = {
            rpm = rpm,
            stress = stress,
            capacity = capacity,
            load = capacity > 0 and (stress / capacity * 100) or 0,
            overstressed = io.stressometer.isOverstressed(),
        },

        boiler = {
            level = tonumber(l1:match("Lvl%s+(%d+)")) or 0,
            size = parseBar(l2, "Size"),
            water = parseBar(l3, "Water"),
            heat = parseBar(l4, "Heat"),
        },

        battery = {
            energy = energy,
            capacity = energyCapacity,
            percent = energyCapacity > 0 and (energy / energyCapacity * 100) or 0,
            maxInsert = io.accumulator.getMaxInsert() or 0,
            maxExtract = io.accumulator.getMaxExtract() or 0,
        },

        motor = {
            rpm = io.motor.getSpeed() or 0,
            consumption = io.motor.getEnergyConsumption() or 0,
            stressCapacity = io.motor.getStressCapacity() or 0,
        },

        control = {
            state = controller.getState(),
            error = controller.getError(),
            automatic = controller.isAutomatic(),
            armed = controller.isArmed(),
            plantOffline = controller.isPlantOffline(),
            mainClutchEngaged = io.mainEngaged(),
            alternatorClutchEngaged = io.alternatorEngaged(),
            genClutchEngaged = io.genEngaged(),
        },
    }
end

return M
