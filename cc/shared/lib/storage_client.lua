local config = require("lib.config")
local protocol = require("lib.protocol")
local machineInfo = require("lib.machine")

local M = {}

local function makeId()
    return "store-" .. tostring(os.getComputerID()) .. "-" .. tostring(os.epoch("utc")) .. "-" .. tostring(math.random(1000, 9999))
end

function M.request(action, namespace, key, value, timeoutSeconds)
    local modem = protocol.findWirelessModem()
    if not modem then return nil, "wireless modem unavailable" end

    local requestChannel = config.channels.storageRequest or 4255
    local responseChannel = config.channels.storageResponse or 4256
    local machine = machineInfo.get()
    local id = makeId()

    modem.open(responseChannel)
    protocol.send(modem, requestChannel, {
        type = "storage_request",
        network = machine.network,
        id = id,
        action = action,
        namespace = namespace or "default",
        key = key,
        value = value,
        origin = machine.key,
        timestamp = protocol.now(),
    })

    local timer = os.startTimer(timeoutSeconds or 3)
    while true do
        local event, p1, p2, p3, p4 = os.pullEvent()

        if event == "timer" and p1 == timer then
            return nil, "storage request timeout"
        end

        if event == "modem_message"
            and p2 == responseChannel
            and type(p4) == "table"
            and p4.type == "storage_response"
            and p4.id == id
        then
            if p4.ok then return p4.value, nil, p4 end
            return nil, p4.error or "storage request failed", p4
        end
    end
end

function M.get(namespace, key, timeoutSeconds)
    return M.request("get", namespace, key, nil, timeoutSeconds)
end

function M.set(namespace, key, value, timeoutSeconds)
    return M.request("set", namespace, key, value, timeoutSeconds)
end

function M.delete(namespace, key, timeoutSeconds)
    return M.request("delete", namespace, key, nil, timeoutSeconds)
end

function M.list(namespace, timeoutSeconds)
    return M.request("list", namespace, nil, nil, timeoutSeconds)
end

function M.ping(timeoutSeconds)
    return M.request("ping", "_system", nil, nil, timeoutSeconds)
end

return M
