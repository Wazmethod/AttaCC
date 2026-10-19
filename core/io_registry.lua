local function ioConfig()
    if not fs.exists("/etc/io.lua") then return {} end
    local ok,data=pcall(dofile,"/etc/io.lua")
    if not ok or type(data)~="table" then error("invalid /etc/io.lua") end
    return data
end

local M = {}

local function bindingTable()
    local io=ioConfig()
    return (io.io and io.io.bindings) or io.bindings or {}
end

local function resolvePeripheral(binding)
    if binding.peripheral and binding.peripheral ~= "" and binding.peripheral ~= "auto" then
        if peripheral.isPresent(binding.peripheral) then
            return peripheral.wrap(binding.peripheral), binding.peripheral
        end
        return nil, binding.peripheral
    end

    if binding.type then
        local names = {}
        for _, name in ipairs(peripheral.getNames()) do
            local kinds = {peripheral.getType(name)}
            for _, kind in ipairs(kinds) do
                if kind == binding.type then names[#names + 1] = name; break end
            end
        end
        if #names == 1 then return peripheral.wrap(names[1]), names[1] end
        if #names > 1 then return nil, "ambiguous peripheral type: " .. binding.type end
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

-- Application requirements are logical roles, not hardcoded hardware names.
function M.requirements()
    local merged={}
    local config=ioConfig()
    for role,req in pairs((config.io and config.io.requirements) or config.requirements or {}) do merged[role]=req end
    local catalogOk,catalog=pcall(require,"lib.io_catalog")
    if catalogOk then for role,req in pairs(catalog.all()) do merged[role]=req end end
    local ok,decl=pcall(require,"lib.io_declarations")
    if ok then for role,req in pairs(decl.all()) do merged[role]=req end end
    return merged
end

local function matchesType(name, expected)
    if not peripheral.isPresent(name) then return false end
    for _, kind in ipairs({ peripheral.getType(name) }) do
        if kind == expected then return true end
    end
    return false
end

function M.candidates(role, declared)
    local requirement = declared or M.requirements()[role]
    if not requirement then return {} end
    if requirement.type=="redstone" then return {"top","bottom","left","right","front","back"} end
    local available = {}
    for _,name in ipairs(peripheral.getNames()) do
        if matchesType(name, requirement.type) then
            available[#available+1] = name
        end
    end
    table.sort(available)
    return available
end

function M.resolve(role, declared)
    local requirement = declared or M.requirements()[role]
    if not requirement then return nil, "unknown hardware requirement: " .. tostring(role) end
    local binding = bindingTable()[role]
    if binding and binding.disabled == true then return nil,"role skipped (optional)" end
    if binding and binding.driver then
        return require("lib.io_drivers").resolve(binding,requirement)
    end
    if requirement.type=="redstone" then
        if binding and binding.kind=="redstone" and binding.side then
            local valid = false
            for _,side in ipairs(redstone.getSides()) do
                if side == binding.side then valid = true; break end
            end
            if not valid then return nil,"invalid redstone side: " .. tostring(binding.side) end
            if binding.relay and not peripheral.isPresent(binding.relay) then
                return nil,"redstone relay unavailable: " .. tostring(binding.relay)
            end
            return binding,nil,(binding.relay and (binding.relay .. ":") or "") .. binding.side
        end
        return nil,"redstone side not configured; run ioctl init"
    end
    if binding and binding.peripheral and binding.peripheral ~= "auto" then
        if matchesType(binding.peripheral, requirement.type) then
            return peripheral.wrap(binding.peripheral), nil, binding.peripheral
        end
        return nil, "configured peripheral unavailable or wrong type: " .. tostring(binding.peripheral)
    end
    local candidates = M.candidates(role, requirement)
    if #candidates == 1 then
        return peripheral.wrap(candidates[1]), nil, candidates[1]
    end
    if #candidates > 1 then
        return nil, "ambiguous auto-binding (" .. table.concat(candidates,", ") .. "); run ioctl init"
    end
    return nil, "no matching " .. tostring(requirement.type) .. " peripheral"
end

-- Invoke a peripheral method on a declared logical role, without bypassing
-- ambiguity or explicit assignment checks. A method is not an I/O binding.
function M.call(role, method, ...)
    local device, err = M.resolve(role)
    if not device then return nil, err end
    if type(method) ~= "string" or not method:match("^[%a_][%w_]*$") then
        return nil, "invalid peripheral method"
    end
    if type(device[method]) ~= "function" then return nil, "method unavailable: " .. method end
    local args = table.pack(...)
    local ok, result = pcall(device[method], table.unpack(args, 1, args.n))
    if not ok then return nil, result end
    return result
end

function M.validateRequirements()
    local result, fatal = {}, false
    for role, requirement in pairs(M.requirements()) do
        local device, err, name = M.resolve(role)
        local level = device and "ok" or (requirement.required and "error" or "warning")
        if level == "error" then fatal = true end
        result[#result+1] = {
            role=role, level=level, required=requirement.required == true,
            peripheral=name, error=err, description=requirement.description,
        }
    end
    table.sort(result, function(a,b) return a.role < b.role end)
    return result, not fatal
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

function M.read(name, fallback)
    local b = bindingTable()[name] or fallback
    if not b then return nil, "unknown binding: " .. tostring(name) end
    if (b.direction or "input") == "output" and not (b.kind == "redstone" and b.readOutput) then return nil, "binding is output-only" end

    if b.driver then
        local value,err=require("lib.io_drivers").read(b)
        if value==nil then return nil,err end
        if b.invert and type(value)=="boolean" then value=not value end
        return transformRead(value,b)
    end

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
            local getter = b.readOutput and relay.getOutput or relay.getInput
            if type(getter) ~= "function" then return nil, "relay method unavailable" end
            local ok, result = pcall(getter, side)
            if not ok then return nil, result end
            value = result
        else
            value = b.readOutput and redstone.getOutput(side) or redstone.getInput(side)
        end

        if b.invert then value = not value end
        return value
    end

    return nil, "unsupported binding kind: " .. tostring(b.kind)
end

function M.write(name, value, fallback)
    local b = bindingTable()[name] or fallback
    if not b then return false, "unknown binding: " .. tostring(name) end
    if b.direction == "input" then return false, "binding is input-only" end

    value = transformWrite(value, b)

    if b.driver then return require("lib.io_drivers").write(b,value) end

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
