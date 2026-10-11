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
    return {
        type = "module_command",
        module = moduleName,
        command = command,
        origin = origin,
        id = id,
        args = args or {},
        targetMachine = targetMachine,
        timestamp = M.now(),
    }
end

-- Compatibility wrapper for the first infrastructure module.
function M.makeCommand(command, origin, id, extra)
    return M.makeModuleCommand("steamplant", command, origin, id, extra or {})
end

function M.normalizeModuleCommand(msg, legacyTarget, moduleName)
    if type(msg) ~= "table" then return nil end

    if msg.type == "module_command" and msg.module == moduleName then
        return msg
    end

    if msg.target == legacyTarget and msg.command then
        local args = {}
        if msg.rpm ~= nil then args.rpm = msg.rpm end

        return {
            type = "module_command",
            module = moduleName,
            command = msg.command,
            origin = msg.origin,
            id = msg.id,
            args = args,
            timestamp = msg.timestamp,
            legacy = true,
        }
    end

    return nil
end

return M
