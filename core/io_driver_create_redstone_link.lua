-- Adapter for CC: Redstone Link Bridge and CC: Create Redstone Link.
-- Both expose the redstone_link_bridge peripheral type on NeoForge 1.21.1.
local M={}

local function hasType(name,expected)
    if type(name)~="string" or not peripheral.isPresent(name) then return false end
    for _,kind in ipairs({peripheral.getType(name)}) do
        if kind==expected then return true end
    end
    return false
end

function M.matches(name)
    return hasType(name,"redstone_link_bridge")
end

local function validFrequency(value)
    -- The mods accept empty slots, represented by the empty string.
    return type(value)=="string" and
        (value=="" or value:match("^[%w_.%-]+:[%w_./%-]+$")~=nil)
end

local function validColor(value)
    return value==nil or (type(value)=="number" and value%1==0
        and value>=0 and value<=0xFFFFFF)
end

local function hasMethod(name,method)
    for _,entry in ipairs(peripheral.getMethods(name) or {}) do
        if entry==method then return true end
    end
    return false
end

function M.validate(binding,requirement)
    if type(binding)~="table" or
        not M.matches(binding.peripheral) then
        return false,"configured Redstone Link Bridge unavailable or wrong type"
    end
    if not validFrequency(binding.freq1) or not validFrequency(binding.freq2) then
        return false,"Redstone Link frequency slots must be item IDs or empty strings"
    end
    if not validColor(binding.color1) or not validColor(binding.color2) then
        return false,"invalid Redstone Link color (expected RGB integer)"
    end
    -- Colors are supported by the watch-capable CC: Create variant, but
    -- not guaranteed by the basic CC: Redstone Link Bridge.
    if (binding.color1~=nil or binding.color2~=nil)
        and not hasMethod(binding.peripheral,"watchLinkSignal") then
        return false,"colored links require the CC: Create Redstone Link bridge"
    end
    local direction=(requirement and requirement.direction) or binding.direction or "input"
    if direction=="input" or direction=="inout" then
        if not hasMethod(binding.peripheral,"getLinkSignal") then
            return false,"bridge missing getLinkSignal"
        end
    end
    if direction=="output" or direction=="inout" then
        if not hasMethod(binding.peripheral,"sendLinkSignal") then
            return false,"bridge missing sendLinkSignal"
        end
    end
    return true
end

function M.describe(binding)
    return binding.peripheral.." ["..binding.freq1.." + "..binding.freq2.."]"
end

local function callBridge(binding,method,strength)
    local ok,value
    if strength==nil then
        ok,value=pcall(peripheral.call,binding.peripheral,method,
            binding.freq1,binding.freq2,binding.color1,binding.color2)
    else
        ok,value=pcall(peripheral.call,binding.peripheral,method,
            binding.freq1,binding.freq2,strength,binding.color1,binding.color2)
    end
    if not ok then return nil,tostring(value) end
    return value
end

function M.read(binding)
    local valid,err=M.validate(binding,{direction="input"})
    if not valid then return nil,err end
    local strength,readErr=callBridge(binding,"getLinkSignal")
    if strength==nil then return nil,readErr or "bridge returned no signal" end
    if type(strength)~="number" then return nil,"bridge returned nonnumeric signal" end
    return strength>0
end

function M.write(binding,value)
    local valid,err=M.validate(binding,{direction="output"})
    if not valid then return false,err end
    local strength
    if type(value)=="boolean" then strength=value and 15 or 0
    elseif type(value)=="number" and value%1==0 and value>=0 and value<=15 then
        strength=value
    else return false,"bridge output expects boolean or integer 0..15" end
    local _,sendError=callBridge(binding,"sendLinkSignal",strength)
    if sendError then return false,sendError end
    return true
end

return M
