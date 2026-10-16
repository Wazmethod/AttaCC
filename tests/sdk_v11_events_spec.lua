-- Standalone Lua contract test; no CraftOS modem required.
package.path="./core/?.lua;"..package.path
textutils={serializeJSON=function(value)
    assert(type(value)=="string")
    return string.format("%q",value)
end}
package.preload["lib.sha256"]=function() return dofile("core/sha256.lua") end
local auth=require("sdk_auth")
local secret=string.rep("k",40)
local frame={type="attacc.sdk.event.v1",topic="node.status",
    origin="node-a",network="plant",timestamp=100000,
    payload={type="attacc.sdk.node.v1",key="node-a",network="plant"}}
local sig,err=auth.signEvent(frame,secret)
assert(sig,err)
frame.auth={version=1,signature=sig}
local policy={peers={["node-a"]={enabled=true,events=true,key=secret,controls={}}}}
local function verdict(expected,message,config,network,now)
    local ok=auth.verifyEvent(message,config or policy,network or "plant",now or 100000)
    assert(ok==expected,"expected "..tostring(expected)..", got "..tostring(ok))
end
verdict(true,frame)
local altered={}
for k,v in pairs(frame) do altered[k]=v end
altered.payload={type="attacc.sdk.node.v1",key="node-b",network="plant"}
verdict(false,altered)
altered.payload=frame.payload
altered.auth=nil
verdict(false,altered)
verdict(false,frame,{peers={["node-a"]={enabled=true,key=secret}}})
verdict(false,frame,policy,"other-network")
verdict(false,frame,policy,"plant",111001)
print("SDK signed event contract checks passed")
