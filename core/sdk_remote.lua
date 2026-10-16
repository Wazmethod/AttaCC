-- SDK remote command client. Fail closed: never downgrade to legacy commands.
local M={}
function M.new(app,transport,options)
    options=options or {}
    local commands=require("lib.sdk_commands")
    local pending={}
    local seq=0
    local timeout=tonumber(options.timeoutMs) or 5000
    local maxRetries=tonumber(options.maxRetries) or 2
    local function now() return os.epoch("utc") end
    local self={}
    function self:request(target,appId,control,args,callback)
        if type(target)~="string" or target=="" then return false,"target required" end
        seq=seq+1
        local id="sdk-"..os.getComputerID().."-"..now().."-"..seq
        local machine=transport.machine
        local auth=require("lib.sdk_auth").load()
        local client=auth and auth.client
        if not client or client.enabled~=true or type(client.origin)~="string" then
            return false,"SDK command client not configured"
        end
        local request,err=commands.clientRequest(appId,control,
            client.origin,target,machine.network,id,args or {})
        if not request then return false,err end
        local item={id=id,module=appId,targetMachine=target,command=control,
            sdk=true,network=machine.network,frame=request,callback=callback,tries=0,sent=0}
        pending[id]=item
        self:tick(true)
        return true,id
    end
    function self:handle(channel,message)
        if channel~=transport.channels.ack or not commands.isAck(message) then return false end
        local item=pending[message.id]
        if not item or not commands.acceptAck(message,item) then return false end
        pending[message.id]=nil
        if item.callback then pcall(item.callback,message.ok==true,message.error,item,message) end
        return true
    end
    function self:tick(force)
        for id,item in pairs(pending) do
            if force and item.sent==0 or (item.sent>0 and now()-item.sent>=timeout) then
                if item.tries>maxRetries then
                    pending[id]=nil
                    if item.callback then pcall(item.callback,false,"command timeout",item) end
                else
                    transport:send(transport.channels.control,item.frame)
                    item.tries=item.tries+1
                    item.sent=now()
                end
            end
        end
    end
    function self:pending() return pending end
    return self
end
return M
