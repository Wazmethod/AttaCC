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

return M
