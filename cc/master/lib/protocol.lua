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

function M.makeCommand(command, origin, id, extra)
    local msg = extra or {}
    msg.target = "steam_plant"
    msg.command = command
    msg.origin = origin
    msg.id = id
    msg.timestamp = M.now()
    return msg
end

return M
