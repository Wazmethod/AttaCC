-- SDK transport service for app hosts. No application owns modem channels.
local M={}
function M.new(app,settings)
    settings=settings or {}
    local protocol=require("lib.protocol")
    local auth=require("lib.sdk_auth")
    local commands=require("lib.sdk_commands")
    local snapshot=require("lib.sdk_snapshot")
    local machine=require("lib.machine").get(app.id)
    local modem=protocol.findWirelessModem()
    if not modem then return nil,"wireless modem unavailable" end
    local channels=settings.channels or {}
    local control=channels.sdkControl or 4257
    local ack=channels.sdkAck or 4258
    local data=channels.sdkSnapshot or 4259
    modem.open(control)
    local self={modem=modem,machine=machine}
    local dispatcher=commands.new(app,{
        machine=machine.key,network=machine.network,
        authorize=function(request)
            local policy=auth.load()
            return policy and auth.authorize(request,policy) or false
        end,
        signAck=function(reply,request)
            local policy=auth.load()
            local peer=policy and policy.peers and policy.peers[request.origin]
            if not peer then return nil end
            return auth.signAck(reply,peer.key)
        end,
    })
    function self:publish()
        local frame,err=snapshot.frame(app:descriptor(),machine.key,machine.network)
        if not frame then return false,err end
        protocol.send(modem,data,frame)
        return true
    end
    function self:handle(channel,message)
        if channel~=control then return false end
        local reply=dispatcher:handle(message)
        if reply then protocol.send(modem,ack,reply); return true end
        return false
    end
    return self
end
return M
