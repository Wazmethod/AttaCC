local machineInfo = require("lib.machine")
local protocol = require("lib.protocol")
local runtime = require("lib.runtime")
local backendFactory = require("lib.storage_backend")

local M = {}

function M.new(modem, config)
    local machine = machineInfo.get()
    local settings = config.storage or {}
    local backend = backendFactory.new(config)

    local self = {
        machine = machine,
        backend = backend,
        requestChannel = config.channels.storageRequest or 4255,
        responseChannel = config.channels.storageResponse or 4256,
    }

    modem.open(self.requestChannel)

    local function reply(request, ok, value, err)
        protocol.send(modem, self.responseChannel, {
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
        })
    end

    function self:stats()
        return backend:stats()
    end

    function self:handle(channel, request)
        if channel ~= self.requestChannel then return false end
        if type(request) ~= "table" or request.type ~= "storage_request" then return false end
        if request.global ~= true and request.network and request.network ~= machine.network then return false end
        if request.targetMachine and request.targetMachine ~= machine.key then return false end
        if not request.id then return false end

        local action = request.action
        local value, err

        if action == "ping" then
            value = backend:ping()
        elseif action == "namespaces" then
            value, err = backend:namespaces()
        elseif action == "list" then
            value, err = backend:list(request.namespace or "default")
        elseif action == "get" then
            value, err = backend:get(request.namespace or "default", request.key)
        elseif action == "set" then
            value, err = backend:set(
                request.namespace or "default",
                request.key,
                request.value,
                request.origin
            )
        elseif action == "rename_identity" then
            value, err = backend:renameIdentity(request.namespace,request.key,
                request.value,request.origin)
        elseif action == "delete" then
            value, err = backend:delete(request.namespace or "default", request.key)
        else
            err = "unknown storage action"
        end

        local ok = err == nil
        reply(request, ok, value, err)

        if ok and (action == "set" or action == "delete") then
            runtime.log("module:storage", "info",
                tostring(action) .. " "
                .. tostring(request.namespace or "default") .. "/"
                .. tostring(request.key) .. " by " .. tostring(request.origin))
        end
        return true
    end

    runtime.log("module:storage", "info", "storage network adapter ready")
    return self
end

return M
