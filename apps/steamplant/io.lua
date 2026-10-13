local config = require("lib.config")

local M = {}

local OUTPUTS_FILE = "/var/lib/steamplant/outputs.json"
local LEGACY_OUTPUTS_FILE = ".steamplant-outputs.json"

local function ensureParent(path)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
end

local TYPES = {
    target = "create_target",
    speedometer = "Create_Speedometer",
    stressometer = "Create_Stressometer",
    motor = "electric_motor",
    accumulator = "modular_accumulator",
    redstoneRelay = "redstone_relay",
}

local outputState = {
    main = nil,
    alternator = nil,
    gen = nil,
    motorRPM = nil,
}

local function find(kind)
    local configured = config.peripherals and config.peripherals[kind]
    if configured and configured ~= "" and peripheral.isPresent(configured) then
        return peripheral.wrap(configured)
    end
    return peripheral.find(TYPES[kind])
end

local function findNamed(name)
    if not name or name == "" then return nil end
    if not peripheral.isPresent(name) then return nil end
    return peripheral.wrap(name)
end

local function resolveRedstoneDevice()
    local rs = config.redstone or {}
    local mode = rs.mode or "auto"

    if mode == "direct" then
        return redstone, "direct", "computer"
    end

    if mode == "relay" or mode == "auto" then
        local relay = nil
        local relayName = rs.relayName

        if relayName and relayName ~= "" then
            relay = findNamed(relayName)
        else
            relay = find("redstoneRelay")
            if relay then
                relayName = peripheral.getName(relay)
            end
        end

        if relay then
            return relay, "relay", relayName or "redstone_relay"
        end

        if mode == "relay" then
            return nil, "relay", relayName or "redstone_relay"
        end
    end

    return redstone, "direct", "computer"
end

local function saveOutputs()
    local ok, encoded = pcall(textutils.serializeJSON, outputState)
    if not ok or not encoded then return false end

    ensureParent(OUTPUTS_FILE)
    local tmp = OUTPUTS_FILE .. ".new"
    local h = fs.open(tmp, "w")
    if not h then return false end

    h.write(encoded)
    h.close()

    if fs.exists(OUTPUTS_FILE) then fs.delete(OUTPUTS_FILE) end
    fs.move(tmp, OUTPUTS_FILE)
    return true
end

local function loadOutputs()
    local source = OUTPUTS_FILE

    if not fs.exists(source) and fs.exists(LEGACY_OUTPUTS_FILE) then
        source = LEGACY_OUTPUTS_FILE
    end

    if not fs.exists(source) then return nil end

    local h = fs.open(source, "r")
    if not h then return nil end

    local raw = h.readAll()
    h.close()

    local ok, data = pcall(textutils.unserializeJSON, raw)
    if not ok or type(data) ~= "table" then return nil end

    if type(data.main) ~= "boolean"
        or type(data.alternator) ~= "boolean"
        or type(data.gen) ~= "boolean"
        or type(data.motorRPM) ~= "number"
    then
        return nil
    end

    -- One-way migration to the generic infrastructure namespace.
    if source == LEGACY_OUTPUTS_FILE then
        outputState = data
        saveOutputs()
        if fs.exists(LEGACY_OUTPUTS_FILE) then fs.delete(LEGACY_OUTPUTS_FILE) end
    end

    return data
end

function M.refresh()
    M.target = find("target") or M.target
    M.speedometer = find("speedometer") or M.speedometer
    M.stressometer = find("stressometer") or M.stressometer
    M.motor = find("motor") or M.motor
    M.accumulator = find("accumulator") or M.accumulator

    local rsDevice, rsMode, rsName = resolveRedstoneDevice()
    if rsDevice then
        M.redstoneDevice = rsDevice
        M.redstoneMode = rsMode
        M.redstoneName = rsName
    end
end

M.refresh()

if not M.target then error("Create Target introuvable") end
if not M.speedometer then error("Speedometer introuvable") end
if not M.stressometer then error("Stressometer introuvable") end
if not M.motor then error("Electric Motor introuvable") end
if not M.accumulator then error("Accumulator introuvable") end
if not M.redstoneDevice then
    error("Redstone I/O introuvable (configure config.redstone.mode/relayName)")
end

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

local function setClutch(side, key, engaged, persist)
    M.refresh()
    if not M.redstoneDevice then
        error("Redstone I/O introuvable")
    end

    M.redstoneDevice.setOutput(side, not engaged)
    outputState[key] = engaged

    if persist ~= false then
        saveOutputs()
    end
end

-- Create clutch: redstone ON = transmission CUT.
function M.setMain(engaged, persist)
    setClutch(config.redstone.mainClutch, "main", engaged and true or false, persist)
end

function M.setAlternator(engaged, persist)
    setClutch(config.redstone.alternatorClutch, "alternator", engaged and true or false, persist)
end

function M.setGen(engaged, persist)
    setClutch(config.redstone.genClutch, "gen", engaged and true or false, persist)
end

local function clutchEngaged(side)
    M.refresh()
    if not M.redstoneDevice then return false end
    return not M.redstoneDevice.getOutput(side)
end

function M.mainEngaged()
    return clutchEngaged(config.redstone.mainClutch)
end

function M.alternatorEngaged()
    return clutchEngaged(config.redstone.alternatorClutch)
end

function M.genEngaged()
    return clutchEngaged(config.redstone.genClutch)
end

function M.getRedstoneStatus()
    M.refresh()
    return {
        mode = M.redstoneMode,
        name = M.redstoneName,
        available = M.redstoneDevice ~= nil,
    }
end

function M.getSpeed()
    return M.call("speedometer", "getSpeed", 0)
end

local function setMotorRaw(rpm)
    M.refresh()
    local motor = M.motor
    if not motor then return false, "Electric Motor introuvable" end

    local direction = tonumber(config.motor and config.motor.direction) or 1
    direction = direction < 0 and -1 or 1
    local physicalRPM = rpm == 0 and 0 or (rpm * direction)

    local ok, err
    if physicalRPM == 0 then
        ok, err = pcall(function() motor.stop() end)
    else
        ok, err = pcall(function() motor.setSpeed(physicalRPM) end)
    end

    if ok then return true end

    M.motor = find("motor")
    if not M.motor then return false, tostring(err) end

    if physicalRPM == 0 then
        return pcall(function() M.motor.stop() end)
    end

    return pcall(function() M.motor.setSpeed(physicalRPM) end)
end

function M.setMotorSpeed(rpm, persist)
    local ok, err = setMotorRaw(rpm)
    if ok then
        outputState.motorRPM = rpm
        if persist ~= false then saveOutputs() end
    end
    return ok, err
end

function M.stopMotor(persist)
    return M.setMotorSpeed(0, persist)
end

local function bootClutch(value, name)
    if value == "engaged" then return true end
    if value == "cut" then return false end
    error("Invalid bootState." .. name .. ": " .. tostring(value))
end

function M.restoreOutputs()
    local saved = loadOutputs()
    local source

    if saved then
        outputState = {
            main = saved.main,
            alternator = saved.alternator,
            gen = saved.gen,
            motorRPM = saved.motorRPM,
        }
        source = "persisted"
    else
        outputState = {
            main = bootClutch(config.bootState.main, "main"),
            alternator = bootClutch(config.bootState.alternator, "alternator"),
            gen = bootClutch(config.bootState.gen, "gen"),
            motorRPM = tonumber(config.bootState.motorRPM) or 0,
        }
        source = "config"
    end

    -- Apply the complete topology without writing after every individual output.
    M.setMain(outputState.main, false)
    M.setAlternator(outputState.alternator, false)
    M.setGen(outputState.gen, false)

    local ok, err = setMotorRaw(outputState.motorRPM)
    if not ok then
        return false, err, source
    end

    saveOutputs()
    return true, nil, source
end

function M.getOutputState()
    return {
        main = outputState.main,
        alternator = outputState.alternator,
        gen = outputState.gen,
        motorRPM = outputState.motorRPM,
    }
end

return M
