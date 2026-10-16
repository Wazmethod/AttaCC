-- Minecraft LAN mode smoke checks for the common SDK transport.
package.path="./core/?.lua;"..package.path
local now=100000
local oldEpoch=os.epoch
os.epoch=function() return now end
local sent={}
package.loaded["lib.protocol"]={findWirelessModem=function()
    return {open=function() end}
end,send=function(_,channel,frame) sent[#sent+1]={channel,frame} end}
package.loaded["lib.sdk_auth"]={
    load=function() return nil end,
    verifySnapshot=function() error("unsigned snapshot should not require auth") end,
    verifyEvent=function() error("unsigned event should not require auth") end,
}
package.loaded["lib.sdk_commands"]={new=function() return {handle=function() return nil end} end}
package.loaded["lib.sdk_snapshot"]={frame=function(_,key,network)
    return {type="attacc.sdk.snapshot.v1",machine=key,network=network,
        module="test",timestamp=now,descriptor={schema="attacc.sdk.app.v1",id="test"}}
end}
package.loaded["lib.machine"]={get=function()
    return {key="master",network="plant"}
end}
local snapshots,events=0,0
local app={id="master_preview",networkSubscriptions={["node.status"]={}},
    snapshotListeners={function() end}}
function app:descriptor() return {schema="attacc.sdk.app.v1",id="test"} end
function app:receiveSnapshot(frame) snapshots=snapshots+1;return true end
function app:receiveNetwork(frame) events=events+1;return true end
local transport=require("sdk_transport").new(app,{})
assert(transport:publish())
assert(sent[#sent][2].auth==nil)
assert(transport:publishEvent("node.status",{key="master"}))
assert(sent[#sent][2].auth==nil)
local snap={type="attacc.sdk.snapshot.v1",machine="node",network="plant",
    module="test",timestamp=now,
    descriptor={schema="attacc.sdk.app.v1",id="test"}}
assert(transport:handle(transport.channels.data,snap))
assert(not transport:handle(transport.channels.data,snap))
assert(snapshots==1)
local evt={type="attacc.sdk.event.v1",origin="node",network="plant",
    topic="node.status",timestamp=now,payload={key="node"}}
assert(transport:handle(transport.channels.events,evt))
assert(events==1)
evt.network="different"
assert(not transport:handle(transport.channels.events,evt))
snap.network="different"
assert(not transport:handle(transport.channels.data,snap))
os.epoch=oldEpoch
print("SDK zero-config Minecraft LAN transport smoke checks passed")
