package.path="./core/?.lua;"..package.path
package.loaded["lib.sdk_commands"]={
    clientRequest=function(appId,control,origin,target,network,id,args)
        return {type="test.command",id=id}
    end,
    isAck=function(m) return type(m)=="table" and m.type=="test.ack" end,
    acceptAck=function() return true end,
}
package.loaded["lib.sdk_auth"]={load=function()
    return {client={enabled=true,origin="master"}}
end}
local current=100000
local oldEpoch,oldId=os.epoch,os.getComputerID
os.epoch=function() return current end
os.getComputerID=function() return 1 end
local remote=require("sdk_remote")
local sent=0
local failed=false
local transport={machine={network="test"},channels={control=4257,ack=4258}}
function transport:send()
    sent=sent+1
    if failed then return false,"modem failure" end
    return true
end
local client=remote.new({},transport,{timeoutMs=100,maxRetries=1})
failed=true
local ok,err=client:request("generator","steamplant","abort",{},function() end)
assert(ok==false and err=="modem failure")
assert(next(client:pending())==nil)
failed=false
local success,id=client:request("generator","steamplant","abort",{},function() end)
assert(success and id and next(client:pending())~=nil)
current=current+101
client:tick()
assert(sent==3,"expected initial failure, initial send, one retry")
current=current+101
client:tick()
assert(next(client:pending())==nil,"timed out requests must be removed")
os.epoch,os.getComputerID=oldEpoch,oldId
print("SDK remote transport failure and retry checks passed")
