package.path="./core/?.lua;"..package.path
local storage=require("sdk_storage")
local app={id="storage_agent",controls={}}
function app:control(id,definition) self.controls[id]=definition end
local calls={}
package.loaded["lib.storage_backend"]={new=function()
    return {
        namespaces=function() return {"alpha","beta"} end,
        list=function(_,namespace) return {"key1"} end,
        get=function(_,namespace,key) return {value=42} end,
        set=function(_,namespace,key,value,origin)
            calls[#calls+1]={namespace,key,value,origin}
            return true
        end
    }
end}
storage.install(app,{enabled=true,actions={
    namespaces=true,get=true,set=false
}})
local control=app.controls.storage_request
assert(control and control.remote==true)
local ok,value=control.run({action="namespaces"})
assert(ok and #ok==2)
local disabled,reason=control.run({action="set",namespace="alpha",
    key="key1",value="new"})
assert(disabled==false and reason=="storage action denied")
local invalid=control.run({action="get",namespace="../wrong",key="x"})
assert(invalid==false)
local remote={calls=0}
function remote:remoteCommand(target,appId,controlName,args,callback)
    self.calls=self.calls+1
    assert(target=="storage-node")
    assert(appId=="storage_agent" and controlName=="storage_request")
    callback(true,nil,nil,{value='["alpha","beta"]'})
    return true,"test-command"
end
textutils={unserializeJSON=function(raw)
    if raw=='["alpha","beta"]' then return {"alpha","beta"} end
    error("bad JSON")
end}
local received
local sent,id=storage.request(remote,"storage-node","namespaces",nil,nil,nil,
    function(success,result,reason)
        assert(success and not reason)
        received=result
    end)
assert(sent and id=="test-command" and #received==2 and remote.calls==1)
local bad=storage.request(remote,"storage-node","delete","../bad","key",nil,
    function() end)
assert(bad==false and remote.calls==1)
print("SDK storage contract tests passed")
