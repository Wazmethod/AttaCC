local config = require("lib.config")
local protocol = require("lib.protocol")
local machineInfo = require("lib.machine")

local M = {}

local function selectedHost()
    local ok, store = pcall(require, "lib.profile_store")
    if not ok or not store or not store.storageConfig then return nil end
    local cfg = store.storageConfig()
    return cfg and cfg.targetMachine or nil
end

local function makeId()
    return "store-" .. tostring(os.getComputerID()) .. "-" .. tostring(os.epoch("utc")) .. "-" .. tostring(math.random(1000, 9999))
end

function M.request(action, namespace, key, value, timeoutSeconds)
    local machine = machineInfo.get()

    if fs.exists("lib/storage_backend.lua") then
        local backend = require("lib.storage_backend").new(config)
        if action == "ping" then
            return backend:ping(), nil
        elseif action == "namespaces" then
            return backend:namespaces(), nil
        elseif action == "list" then
            return backend:list(namespace)
        elseif action == "get" then
            return backend:get(namespace, key)
        elseif action == "set" then
            return backend:set(namespace, key, value, machine.key)
        elseif action == "delete" then
            return backend:delete(namespace, key)
        end
        return nil, "unknown storage action"
    end

    local modem = protocol.findWirelessModem()
    if not modem then return nil, "wireless modem unavailable" end

    local id = makeId()
    local requestChannel = config.channels.storageRequest or 4255
    local responseChannel = config.channels.storageResponse or 4256
    local request = {
        type = "storage_request",
        network = machine.network,
        id = id,
        action = action,
        namespace = namespace or "default",
        key = key,
        value = value,
        origin = machine.key,
        targetMachine = selectedHost(),
        timestamp = protocol.now(),
    }

    modem.open(responseChannel)
    protocol.send(modem, requestChannel, request)

    local timer = os.startTimer(timeoutSeconds or 3)
    while true do
        local event, p1, p2, p3, p4 = os.pullEvent()

        if event == "timer" and p1 == timer then
            return nil, "storage request timeout (network=" .. tostring(machine.network)
                .. ", target=" .. tostring(request.targetMachine or "any")
                .. ", channel=" .. tostring(requestChannel) .. ")"
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

function M.namespaces(timeoutSeconds)
    return M.request("namespaces", "_system", nil, nil, timeoutSeconds)
end

function M.ping(timeoutSeconds)
    return M.request("ping", "_system", nil, nil, timeoutSeconds)
end

return M
