local config = require("lib.config")
local ioRegistry = require("lib.io_registry")

local M = {}

local OUTPUTS_FILE = "/var/lib/steamplant/outputs.json"

local function ensureParent(path)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
end

local outputState = {
    main = nil,
    alternator = nil,
    gen = nil,
    motorRPM = nil,
}

local function find(kind)
    local device = ioRegistry.resolve(kind)
    return device
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
    if not fs.exists(OUTPUTS_FILE) then return nil end

    local h = fs.open(OUTPUTS_FILE, "r")
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

local hardwareStatus, hardwareReady = ioRegistry.validateRequirements()
for _, status in ipairs(hardwareStatus) do
    if status.level == "warning" then
        print("AttaCC I/O warning: " .. status.role .. ": " .. tostring(status.error))
    elseif status.level == "error" then
        printError("AttaCC I/O required: " .. status.role .. ": " .. tostring(status.error))
    end
end
if not hardwareReady then
    error("Required SteamPlant hardware unavailable. Run ioctl init and ioctl check.")
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

-- All SteamPlant sensor reads now go through the common AttaCC SDK.
function M.call(kind, method, default, ...)
    local result, err = require("lib.steamplant_sdk").get():call(kind, method, ...)
    if err then return default end
    if result == nil then return default end
    return result
end

-- SDK owns physical redstone I/O. Legacy profile values are fallback bindings
-- only until each app-qualified role is configured through ioctl init.
local clutchRoles = {
    main = {"main_clutch", "mainClutch"},
    alternator = {"alternator_clutch", "alternatorClutch"},
    gen = {"gen_clutch", "genClutch"},
}
local function clutchBinding(key)
    local name = clutchRoles[key][1]
    if ioRegistry.describe("steamplant." .. name) then return nil end
    local rs = config.redstone or {}
    local mode = rs.mode or "auto"
    local relay = nil
    if mode ~= "direct" then
        local device, err, resolved = ioRegistry.resolve("steamplant.redstoneRelay")
        if device then relay = resolved
        elseif mode == "relay" then return nil, err end
    end
    return {
        kind="redstone", direction="output", side=rs[clutchRoles[key][2]],
        relay=relay, invert=true, readOutput=true,
    }
end
local function setClutch(_, key, engaged, persist)
    local role = clutchRoles[key][1]
    local fallback, err = clutchBinding(key)
    if err then error(err) end
    local ok, reason = require("lib.steamplant_sdk").get():write(role, engaged == true, fallback)
    if not ok then error("clutch " .. key .. ": " .. tostring(reason)) end
    outputState[key] = engaged == true
    if persist ~= false then saveOutputs() end
end
function M.setMain(engaged, persist)
    setClutch(nil, "main", engaged, persist)
end
function M.setAlternator(engaged, persist)
    setClutch(nil, "alternator", engaged, persist)
end
function M.setGen(engaged, persist)
    setClutch(nil, "gen", engaged, persist)
end
local function clutchEngaged(key)
    local role = clutchRoles[key][1]
    local fallback, err = clutchBinding(key)
    if err then return false end
    local value = require("lib.steamplant_sdk").get():read(role, fallback)
    return value == true
end
function M.mainEngaged() return clutchEngaged("main") end
function M.alternatorEngaged() return clutchEngaged("alternator") end
function M.genEngaged() return clutchEngaged("gen") end
function M.getRedstoneStatus()
    local fallback, err = clutchBinding("main")
    local binding = ioRegistry.describe("steamplant.main_clutch") or fallback
    return {
        mode=binding and (binding.relay and "relay" or "direct") or "unavailable",
        name=binding and (binding.relay or "computer") or "unavailable",
        available=binding~=nil and err==nil,
    }
end

function M.getSpeed()
    return M.call("speedometer", "getSpeed", 0)
end

local function setMotorRaw(rpm)
    local direction = tonumber(config.motor and config.motor.direction) or 1
    direction = direction < 0 and -1 or 1
    local physicalRPM = rpm == 0 and 0 or (rpm * direction)
    local sdk = require("lib.steamplant_sdk").get()
    local method = physicalRPM == 0 and "stop" or "setSpeed"
    -- A void CC peripheral method legitimately returns nil on success.
    local _, err
    if physicalRPM == 0 then
        _, err = sdk:call("motor", method)
    else
        _, err = sdk:call("motor", method, physicalRPM)
    end
    if err then return false, err end
    return true
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
