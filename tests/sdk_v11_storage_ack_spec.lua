package.path="./core/?.lua;"..package.path
package.loaded["lib.sha256"]=require("sha256")
textutils={serializeJSON=function(s)
    assert(type(s)=="string")
    return string.format("%q",s)
end}
local auth=require("sdk_auth")
local secret=string.rep("s",48)
local ack={type="attacc.sdk.ack.v1",id="cmd-1",app="storage_agent",
    control="storage_request",origin="workstation",target="store-node",
    network="test",ok=true,timestamp=100000,value='["a","b"]'}
ack.auth={version=1,signature=assert(auth.signAck(ack,secret))}
assert(auth.verifyAck(ack,secret))
ack.value='["a","evil"]'
assert(not auth.verifyAck(ack,secret),"ACK result must be authenticated")
ack.value=string.rep("X",8193)
assert(not auth.signAck(ack,secret),"oversized ACK value must be rejected")
print("SDK signed storage ACK integrity checks passed")
