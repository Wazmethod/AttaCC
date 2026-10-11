local config = require("lib.config")

local M = {}

M.target       = peripheral.find("create_target")
M.speedometer  = peripheral.find("Create_Speedometer")
M.stressometer = peripheral.find("Create_Stressometer")
M.motor        = peripheral.find("electric_motor")
M.accumulator  = peripheral.find("modular_accumulator")

if not M.target then error("Create Target introuvable") end
if not M.speedometer then error("Speedometer introuvable") end
if not M.stressometer then error("Stressometer introuvable") end
if not M.motor then error("Electric Motor introuvable") end
if not M.accumulator then error("Accumulator introuvable") end

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

function M.setMotorSpeed(rpm)
    return pcall(function()
        M.motor.setSpeed(rpm)
    end)
end

function M.stopMotor()
    return pcall(function()
        M.motor.stop()
    end)
end

return M
