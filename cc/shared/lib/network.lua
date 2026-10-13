local bus = require("lib.bus")

local M = {}

function M.findWirelessModem()
    return peripheral.find("modem", function(_, modem)
        return modem.isWireless and modem.isWireless()
    end)
end

function M.new(config, machine)
    local modem = M.findWirelessModem()
    if not modem then return nil, "wireless modem unavailable" end

    local self = {
        modem = modem,
        config = config,
        machine = machine,
        opened = {},
    }

    function self:open(channel)
        channel = tonumber(channel)
        if not channel then return false, "invalid channel" end
        if not self.opened[channel] then
            modem.open(channel)
            self.opened[channel] = true
        end
        return true
    end

    function self:openConfigured(names)
        for _, name in ipairs(names or {}) do
            local channel = config.channels and config.channels[name]
            if channel then self:open(channel) end
        end
    end

    function self:send(channel, message)
        if type(message) ~= "table" then return false, "message table required" end
        if machine then
            message.network = message.network or machine.network
            message.origin = message.origin or machine.key
        end
        modem.transmit(channel, channel, message)
        return true
    end

    function self:accept(message)
        if type(message) ~= "table" then return false end
        if machine and message.network and message.network ~= machine.network then
            return false
        end
        return true
    end

    function self:handle(channel, replyChannel, message, distance)
        if not self:accept(message) then return false end
        bus.emit("network.message", {
            channel = channel,
            replyChannel = replyChannel,
            message = message,
            distance = distance,
        }, {
            remote = true,
            origin = message and message.origin,
        })
        if type(message) == "table" and message.type then
            bus.emit("network." .. tostring(message.type), message, {
                remote = true,
                channel = channel,
                distance = distance,
            })
        end
        return true
    end

    return self
end

return M
