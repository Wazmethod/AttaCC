-- Local CraftOS Lua test; run from the Git checkout: tests/io_drivers_spec.lua
-- No Minecraft block or live Redstone Link is operated.
local previousPeripheral=peripheral
local signals={}
local calls={}
local watchSupported=false
local available=true
local function key(a,b) return a.."|"..b end

peripheral={
    isPresent=function(name) return available and name=="bridge_0" end,
    getNames=function() return available and {"bridge_0"} or {} end,
    getType=function(name) return name=="bridge_0" and "redstone_link_bridge" or nil end,
    getMethods=function(name)
        if name~="bridge_0" then return {} end
        local methods={"getLinkSignal","sendLinkSignal"}
        if watchSupported then
            methods[#methods+1]="watchLinkSignal"
            methods[#methods+1]="unwatchLinkSignal"
        end
        return methods
    end,
    call=function(name,method,a,b,value,color1,color2)
        assert(name=="bridge_0","unexpected target")
        if method=="getLinkSignal" then
            return signals[key(a,b)] or 0
        elseif method=="sendLinkSignal" then
            calls[#calls+1]={method=method,a=a,b=b,value=value,color1=color1,color2=color2}
            signals[key(a,b)]=value
        elseif method=="watchLinkSignal" or method=="unwatchLinkSignal" then
            assert(watchSupported,"watch unavailable")
            calls[#calls+1]={method=method,a=a,b=b}
            return signals[key(a,b)] or 0
        else error("unknown bridge method") end
    end
}
local function suite()
    local driver=dofile("core/io_driver_create_redstone_link.lua")
    local binding={kind="redstone",driver="create.redstone_link",
        peripheral="bridge_0",freq1="minecraft:iron_ingot",
        freq2="minecraft:redstone",direction="inout"}
    local ok,err=driver.validate(binding)
    assert(ok,err)
    assert(driver.read(binding)==false,"zero must read as false")
    assert(driver.write(binding,true))
    assert(calls[#calls].value==15,"true must transmit strength 15")
    assert(driver.read(binding)==true,"nonzero must read as true")
    assert(driver.write(binding,false))
    assert(calls[#calls].value==0,"false must transmit strength 0")
    assert(driver.write(binding,7))
    assert(calls[#calls].value==7)
    assert(driver.write(binding,16)==false,"out of range strength rejected")
    assert(driver.write(binding,"on")==false,"string output rejected")
    local wrong={kind="redstone",driver="create.redstone_link",peripheral="bridge_0",
        freq1="minecraft:iron ingot",freq2="minecraft:redstone"}
    assert(driver.validate(wrong)==false,"malformed item IDs rejected")
    binding.color1=0xFF0000
    assert(driver.validate(binding)==false,"colors not supported by basic bridge")
    watchSupported=true
    assert(driver.validate(binding))
    assert(driver.watch(binding))
    assert(calls[#calls].method=="watchLinkSignal")
    assert(driver.unwatch(binding))
    binding.color1=nil
    available=false
    assert(driver.validate(binding)==false,"missing bridge must be rejected")
end
local ok,err=pcall(suite)
peripheral=previousPeripheral
if not ok then error(err,0) end
print("AttaCC Create Redstone Link driver checks: OK")
