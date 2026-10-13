local machineInfo = require("lib.machine")
local protocol = require("lib.protocol")
local runtime = require("lib.runtime")
local paths = require("lib.paths")

local M = {}

local function ensureParent(path)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
end

local function readJson(path, fallback)
    if not fs.exists(path) then return fallback end
    local h = fs.open(path, "r")
    if not h then return fallback end
    local raw = h.readAll()
    h.close()
    local ok, value = pcall(textutils.unserializeJSON, raw)
    if ok and type(value) == "table" then return value end
    return fallback
end

local function writeJson(path, value)
    ensureParent(path)
    local ok, raw = pcall(textutils.serializeJSON, value)
    if not ok or not raw then return false, "serialization failed" end
    local tmp = path .. ".new"
    local h = fs.open(tmp, "w")
    if not h then return false, "cannot open store" end
    h.write(raw)
    h.close()
    if fs.exists(path) then fs.delete(path) end
    fs.move(tmp, path)
    return true
end

local function validName(value, maxLength)
    return type(value) == "string"
        and value ~= ""
        and #value <= maxLength
        and not value:find("[^%w%._:%-]")
end

function M.new(modem, config)
    local machine = machineInfo.get()
    local settings = config.storage or {}
    local file = settings.file or fs.combine(paths.storage, "store.json")
    local maxValueBytes = tonumber(settings.maxValueBytes) or 4096
    local maxKeys = tonumber(settings.maxKeys) or 512

    local self = {
        machine = machine,
        file = file,
        requestChannel = config.channels.storageRequest or 4255,
        responseChannel = config.channels.storageResponse or 4256,
    }

    modem.open(self.requestChannel)

    local function loadStore()
        local data = readJson(file, {
            format = 1,
            namespaces = {},
            updatedAt = 0,
        })
        data.namespaces = type(data.namespaces) == "table" and data.namespaces or {}
        return data
    end

    local function reply(request, ok, value, err)
        local response = {
            type = "storage_response",
            network = machine.network,
            id = request.id,
            ok = ok == true,
            namespace = request.namespace,
            key = request.key,
            value = value,
            error = err,
            machine = machine.key,
            module = settings.module or "network.storage",
            timestamp = protocol.now(),
        }

        if request._local == true then
            os.queueEvent("attacc_storage_response", request.id, response.ok, response.value, response)
        else
            protocol.send(modem, self.responseChannel, response)
        end
    end

    local function countKeys(data)
        local count = 0
        for _, namespace in pairs(data.namespaces) do
            if type(namespace) == "table" then
                for _ in pairs(namespace) do count = count + 1 end
            end
        end
        return count
    end

    function self:stats()
        local data = loadStore()
        local namespaces = 0
        local keys = 0
        for _, namespace in pairs(data.namespaces or {}) do
            namespaces = namespaces + 1
            if type(namespace) == "table" then
                for _ in pairs(namespace) do keys = keys + 1 end
            end
        end
        return {
            namespaces = namespaces,
            keys = keys,
            maxKeys = maxKeys,
            maxValueBytes = maxValueBytes,
            updatedAt = data.updatedAt or 0,
        }
    end

    function self:handle(channel, request)
        local isLocal = channel == "local" and type(request) == "table" and request._local == true
        if not isLocal and channel ~= self.requestChannel then return false end
        if type(request) ~= "table" or request.type ~= "storage_request" then return false end
        if request.network and request.network ~= machine.network then return false end
        if request.targetMachine and request.targetMachine ~= machine.key then return false end
        if not request.id then return false end

        local action = request.action
        local namespace = request.namespace or "default"

        if not validName(namespace, 64) then
            reply(request, false, nil, "invalid namespace")
            return true
        end

        if action == "ping" then
            reply(request, true, {
                module = settings.module or "network.storage",
                machine = machine.key,
                version = 1,
            })
            return true
        end

        if action ~= "list" and action ~= "namespaces" and not validName(request.key, 128) then
            reply(request, false, nil, "invalid key")
            return true
        end

        local data = loadStore()

        if action == "namespaces" then
            local namespaces = {}
            for name in pairs(data.namespaces) do table.insert(namespaces, name) end
            table.sort(namespaces)
            reply(request, true, namespaces)
            return true
        end

        local bucket = data.namespaces[namespace]
        if type(bucket) ~= "table" then
            bucket = {}
            data.namespaces[namespace] = bucket
        end

        if action == "get" then
            local entry = bucket[request.key]
            reply(request, true, entry and entry.value or nil)
            return true
        end

        if action == "list" then
            local keys = {}
            for key in pairs(bucket) do table.insert(keys, key) end
            table.sort(keys)
            reply(request, true, keys)
            return true
        end

        if action == "set" then
            local okSerialized, serialized = pcall(textutils.serializeJSON, request.value)
            if not okSerialized or not serialized then
                reply(request, false, nil, "value is not serializable")
                return true
            end
            if #serialized > maxValueBytes then
                reply(request, false, nil, "value exceeds maxValueBytes")
                return true
            end
            if not bucket[request.key] and countKeys(data) >= maxKeys then
                reply(request, false, nil, "store key limit reached")
                return true
            end

            bucket[request.key] = {
                value = request.value,
                updatedAt = protocol.now(),
                updatedBy = request.origin,
            }
            data.updatedAt = protocol.now()
            local okWrite, err = writeJson(file, data)
            if not okWrite then
                reply(request, false, nil, err)
                return true
            end
            runtime.log("service:storage", "info",
                "set " .. namespace .. "/" .. request.key .. " by " .. tostring(request.origin))
            reply(request, true, true)
            return true
        end

        if action == "delete" then
            bucket[request.key] = nil
            data.updatedAt = protocol.now()
            local okWrite, err = writeJson(file, data)
            if not okWrite then
                reply(request, false, nil, err)
                return true
            end
            runtime.log("service:storage", "info",
                "delete " .. namespace .. "/" .. request.key .. " by " .. tostring(request.origin))
            reply(request, true, true)
            return true
        end

        reply(request, false, nil, "unknown storage action")
        return true
    end

    runtime.log("service:storage", "info", "network shared store ready")
    return self
end

return M
