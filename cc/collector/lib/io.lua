local config = require("lib.config")

local M = {}

local TYPES = {
    target = "create_target",
    speedometer = "Create_Speedometer",
    stressometer = "Create_Stressometer",
    motor = "electric_motor",
    accumulator = "modular_accumulator",
}

local function find(kind)
    return peripheral.find(TYPES[kind])
end

function M.refresh()
    M.target = find("target") or M.target
    M.speedometer = find("speedometer") or M.speedometer
    M.stressometer = find("stressometer") or M.stressometer
    M.motor = find("motor") or M.motor
    M.accumulator = find("accumulator") or M.accumulator
end

M.refresh()

if not M.target then error("Create Target introuvable") end
if not M.speedometer then error("Speedometer introuvable") end
if not M.stressometer then error("Stressometer introuvable") end
if not M.motor then error("Electric Motor introuvable") end
if not M.accumulator then error("Accumulator introuvable") end

-- Call a peripheral method defensively. Create/CC:C Bridge peripherals can
-- disappear briefly when a kinetic network changes state. If that happens,
-- rediscover the peripheral and retry once instead of killing telemetry.
function M.call(kind, method, default, ...)
    local args = table.pack(...)
    local p = M[kind]

    local function invoke(device)
        if not device or type(device[method]) ~= "function" then
            return false, nil
        end
        return pcall(function()
            return device[method](table.unpack(args, 1, args.n))
        end)
    end

    local ok, value = invoke(p)
    if ok then return value end

    M[kind] = find(kind)
    ok, value = invoke(M[kind])
    if ok then return value end

    return default
end

-- Create clutch: redstone ON = transmission CUT.
function M.setMain(engaged)
    redstone.setOutput(config.redstone.mainClutch, not engaged)
end

function M.setAlternator(engaged)
    redstone.setOutput(config.redstone.alternatorClutch, not engaged)
end

function M.setGen(engaged)
    redstone.setOutput(config.redstone.genClutch, not engaged)
end

function M.mainEngaged()
    return not redstone.getOutput(config.redstone.mainClutch)
end

function M.alternatorEngaged()
    return not redstone.getOutput(config.redstone.alternatorClutch)
end

function M.genEngaged()
    return not redstone.getOutput(config.redstone.genClutch)
end

function M.getSpeed()
    return M.call("speedometer", "getSpeed", 0)
end

function M.setMotorSpeed(rpm)
    M.refresh()
    local motor = M.motor
    if not motor then return false, "Electric Motor introuvable" end

    local ok, err = pcall(function()
        motor.setSpeed(rpm)
    end)

    if ok then return true end

    M.motor = find("motor")
    if not M.motor then return false, tostring(err) end

    return pcall(function()
        M.motor.setSpeed(rpm)
    end)
end

function M.stopMotor()
    M.refresh()
    local motor = M.motor
    if not motor then return false, "Electric Motor introuvable" end

    local ok, err = pcall(function()
        motor.stop()
    end)

    if ok then return true end

    M.motor = find("motor")
    if not M.motor then return false, tostring(err) end

    return pcall(function()
        M.motor.stop()
    end)
end

return M
