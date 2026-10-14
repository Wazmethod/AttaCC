local machineInfo = require("lib.machine")

local M = {}

function M.now()
    return os.epoch("utc")
end

function M.findWirelessModem()
    return peripheral.find("modem", function(_, p)
        return p.isWireless and p.isWireless()
    end)
end

function M.send(modem, channel, message)
    modem.transmit(channel, channel, message)
end

function M.makeModuleCommand(moduleName, command, origin, id, args, targetMachine)
    local machine = machineInfo.get()
    return {
        type = "module_command",
        network = machine.network,
        module = moduleName,
        command = command,
        origin = origin,
        id = id,
        args = args or {},
        targetMachine = targetMachine,
        timestamp = M.now(),
    }
end

function M.normalizeModuleCommand(msg, moduleName)
    if type(msg) ~= "table" then return nil end
    if msg.type == "module_command" and msg.module == moduleName then
        return msg
    end
    return nil
end

-- Optional receive-side validation for sensitive machine commands.
-- Opt-in: applications can call this before acting on network messages.
function M.validateCommand(message, expectedModule, network, maxAgeMs)
    if type(message) ~= "table" then return false, "message is not a table" end
    if message.type ~= "module_command" then return false, "not a module command" end
    if message.module ~= expectedModule then return false, "wrong module" end
    if network and message.network ~= network then return false, "wrong network" end
    if type(message.command) ~= "string" or message.command == "" or #message.command > 64 then
        return false, "invalid command"
    end
    if type(message.origin) ~= "string" or message.origin == "" or #message.origin > 128 then
        return false, "missing origin"
    end
    if message.targetMachine ~= nil and type(message.targetMachine) ~= "string" then
        return false, "invalid target"
    end
    if type(message.timestamp) ~= "number" then return false, "missing timestamp" end
    local age = M.now() - message.timestamp
    local allowedAge = maxAgeMs or 30000
    if age > allowedAge or age < -5000 then return false, "stale command" end
    if message.args ~= nil and type(message.args) ~= "table" then return false, "invalid args" end
    return true
end

return M
