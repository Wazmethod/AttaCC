local config = require("lib.config")

local M = {}

local function bindingTable()
    return (config.io and config.io.bindings) or {}
end

local function resolvePeripheral(binding)
    if binding.peripheral and binding.peripheral ~= "" and peripheral.isPresent(binding.peripheral) then
        return peripheral.wrap(binding.peripheral), binding.peripheral
    end

    if binding.type then
        local p = peripheral.find(binding.type)
        if p then return p, peripheral.getName(p) end
    end

    return nil, binding.peripheral or binding.type
end

local function transformRead(value, binding)
    if type(value) == "number" then
        value = value * (tonumber(binding.multiplier) or 1)
        value = value + (tonumber(binding.offset) or 0)
    end
    return value
end

local function transformWrite(value, binding)
    if type(value) == "number" then
        value = value * (tonumber(binding.multiplier) or 1)
        value = value + (tonumber(binding.offset) or 0)
    end
    if binding.invert and type(value) == "boolean" then value = not value end
    return value
end

function M.list()
    local out = {}
    for name, binding in pairs(bindingTable()) do
        table.insert(out, {
            name = name,
            direction = binding.direction or "input",
            kind = binding.kind or "peripheral",
            binding = binding,
        })
    end
    table.sort(out, function(a,b) return a.name < b.name end)
    return out
end

function M.describe(name)
    return bindingTable()[name]
end

function M.read(name)
    local b = bindingTable()[name]
    if not b then return nil, "unknown binding: " .. tostring(name) end
    if (b.direction or "input") == "output" then return nil, "binding is output-only" end

    if b.kind == "peripheral" then
        local p = resolvePeripheral(b)
        if not p then return nil, "peripheral unavailable" end
        local method = b.method
        if type(method) ~= "string" or type(p[method]) ~= "function" then
            return nil, "method unavailable: " .. tostring(method)
        end
        local ok, value = pcall(p[method], table.unpack(b.args or {}))
        if not ok then return nil, value end
        return transformRead(value, b)
    end

    if b.kind == "redstone" then
        local side = b.side
        if not side then return nil, "redstone side missing" end

        local value
        if b.relay then
            if not peripheral.isPresent(b.relay) then return nil, "relay unavailable" end
            local relay = peripheral.wrap(b.relay)
            local ok, result = pcall(relay.getInput, side)
            if not ok then return nil, result end
            value = result
        else
            value = redstone.getInput(side)
        end

        if b.invert then value = not value end
        return value
    end

    return nil, "unsupported binding kind: " .. tostring(b.kind)
end

function M.write(name, value)
    local b = bindingTable()[name]
    if not b then return false, "unknown binding: " .. tostring(name) end
    if b.direction == "input" then return false, "binding is input-only" end

    value = transformWrite(value, b)

    if b.kind == "peripheral" then
        local p = resolvePeripheral(b)
        if not p then return false, "peripheral unavailable" end
        local method = b.method
        if type(method) ~= "string" or type(p[method]) ~= "function" then
            return false, "method unavailable: " .. tostring(method)
        end
        local args = {}
        for _, v in ipairs(b.args or {}) do table.insert(args, v) end
        table.insert(args, value)
        local ok, err = pcall(p[method], table.unpack(args))
        if not ok then return false, err end
        return true
    end

    if b.kind == "redstone" then
        local side = b.side
        if not side then return false, "redstone side missing" end

        if b.relay then
            if not peripheral.isPresent(b.relay) then return false, "relay unavailable" end
            local relay = peripheral.wrap(b.relay)
            local ok, err = pcall(relay.setOutput, side, value and true or false)
            if not ok then return false, err end
            return true
        end

        redstone.setOutput(side, value and true or false)
        return true
    end

    return false, "unsupported binding kind: " .. tostring(b.kind)
end

return M
