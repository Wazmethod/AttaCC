-- Signed snapshot contract without CraftOS hardware.
package.path="./core/?.lua;"..package.path
package.preload["lib.sha256"]=function() return dofile("core/sha256.lua") end
textutils={serializeJSON=function(value)
    assert(type(value)=="string")
    return string.format("%q",value)
end}
local auth=require("sdk_auth")
local secret=string.rep("z",40)
local frame={type="attacc.sdk.snapshot.v1",schema="attacc.sdk.app.v1",
    module="steamplant",machine="generator",network="plant",timestamp=100000,
    descriptor={schema="attacc.sdk.app.v1",id="steamplant",
        data={{id="rpm",value=80}},graphs={},controls={},views={}}}
local signature,err=auth.signSnapshot(frame,secret)
assert(signature,err)
frame.auth={version=1,signature=signature}
local policy={peers={generator={enabled=true,snapshots=true,key=secret}}}
local function verify(expected,object,permissions,network,clock)
    local result=auth.verifySnapshot(object,permissions or policy,
        network or "plant",clock or 100000)
    assert(result==expected,"wrong snapshot verification result")
end
verify(true,frame)
local changed={}
for k,v in pairs(frame) do changed[k]=v end
changed.descriptor={schema="attacc.sdk.app.v1",id="steamplant",
    data={{id="rpm",value=999}},graphs={},controls={},views={}}
verify(false,changed)
changed.descriptor=frame.descriptor
changed.auth=nil
verify(false,changed)
verify(false,frame,{peers={generator={enabled=true,key=secret}}})
verify(false,frame,policy,"other-network")
verify(false,frame,policy,"plant",111001)
changed.auth=frame.auth
changed.machine="forged"
verify(false,changed)
changed.machine="generator"
changed.module="other"
verify(false,changed)
print("SDK signed snapshot contract checks passed")
