local machineInfo = require("lib.machine")

local M = {}

function M.new()
    local localMachine = machineInfo.get()
    local self = {
        handlers = {},
        network = localMachine.network,
    }

    function self:register(moduleName, handler)
        if type(moduleName) ~= "string" or moduleName == "" then
            error("moduleName must be a non-empty string")
        end
        if type(handler) ~= "function" then
            error("module handler must be a function")
        end
        self.handlers[moduleName] = handler
    end

    function self:dispatch(message, ...)
        if type(message) ~= "table" then return false end
        if message.network and message.network ~= self.network then return false end

        local moduleName = message.module

        -- Legacy steam-plant messages are mapped only at the edge. New
        -- infrastructure modules should always send an explicit module name.
        if not moduleName and message.target == "steam_plant" then
            moduleName = "steamplant"
        end

        local handler = moduleName and self.handlers[moduleName] or nil
        if not handler then return false end

        handler(message, ...)
        return true
    end

    function self:list()
        local out = {}
        for name in pairs(self.handlers) do table.insert(out, name) end
        table.sort(out)
        return out
    end

    return self
end

return M
