-- Run from repository root: lua tests/sdk_v11_admin_spec.lua
package.path="./core/?.lua;"..package.path
local originalEpoch=os.epoch
os.epoch=function() return 100000 end
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local admin=require("sdk_node_admin")
local app={controls={}}
function app:control(id,definition) self.controls[id]=definition end
function app:deferAfterAck(callback)
    self.deferred=callback
    return true
end
admin.install(app,{enabled=false,actions={reboot=true,package_update=true}})
eq(app.controls.node_reboot.enabled(),false)
local ok=app.controls.node_reboot.run({confirm=true})
eq(ok,false)
local active={controls={}}
function active:control(id,definition) self.controls[id]=definition end
function active:deferAfterAck(callback) self.deferred=callback;return true end
admin.install(active,{enabled=true,actions={reboot=true}})
eq(active.controls.node_reboot.enabled(),true)
local accepted=active.controls.node_reboot.run({confirm=false})
eq(accepted,false)
accepted=active.controls.node_reboot.run({confirm=true})
eq(accepted,true)
assert(type(active.deferred)=="function")
eq(active.controls.node_package_update.enabled(),false)
local gate=require("sdk_web_commands")
local requests={}
local client={}
function client:remoteCommand(target,appId,control,args,callback)
    requests[#requests+1]={target=target,appId=appId,control=control,args=args}
    callback(true,nil,nil,{id="sdk-test"})
    return true,"sdk-test"
end
local policy={enabled=true,network="test-network",
    rules={steamplant={targets={machine_a={controls={arm=true}}}}}}
local g=gate.new(client,policy)
local request={type="attacc.sdk.web.command.v1",id="web-1",
    timestamp=100000,network="test-network",target="machine_a",
    app="steamplant",control="arm",args={}}
local callbackOk=false
local good,id=g:execute(request,function(ok) callbackOk=ok end)
eq(good,true);eq(id,"sdk-test");eq(callbackOk,true);eq(#requests,1)
good=g:execute(request,function() end);eq(good,false)
request.id="web-2";request.network="wrong"
good=g:execute(request,function() end);eq(good,false)
request.id="web-3";request.network="test-network";request.control="disarm"
good=g:execute(request,function() end);eq(good,false)
local off=gate.new(client,{enabled=false,network="test-network",rules=policy.rules})
request.control="arm";request.id="web-4"
good=off:execute(request,function() end);eq(good,false)
os.epoch=originalEpoch
print("SDK V1.1 node admin and Web command contract checks passed")
