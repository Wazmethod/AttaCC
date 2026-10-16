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
    local events=channels.sdkEvents or 4260
    modem.open(control)
    if next(app.networkSubscriptions or {}) then modem.open(events) end
    if type(app.snapshotListeners)=="table" and #app.snapshotListeners>0 then modem.open(data) end
    local self={modem=modem,machine=machine,channels={control=control,ack=ack,data=data,events=events}}
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
    function self:send(channel,message)
        if type(message)~="table" then return false,"message required" end
        local ok,err=pcall(protocol.send,modem,channel,message)
        if not ok then return false,tostring(err) end
        return true
    end
    function self:subscribeAck() modem.open(ack) end
    local recentEvents={}
    local recentSnapshots={}
    local lastEventSweep=0
    local function sweepReplay(stamp)
        if stamp-lastEventSweep<10000 then return end
        for _,cache in ipairs({recentEvents,recentSnapshots}) do
            for signature,seen in pairs(cache) do
                if stamp-seen>30000 then cache[signature]=nil end
            end
        end
        lastEventSweep=stamp
    end
    -- LAN telemetry and discovery are intentionally unsigned.
    -- HMAC is reserved exclusively for remote control requests and ACKs.
    function self:publishEvent(topic,payload)
        if type(topic)~="string" or not topic:match("^[%w_.%-]+$")
            or type(payload)~="table" then return false,"invalid SDK event" end
        return self:send(events,{
            type="attacc.sdk.event.v1",topic=topic,
            payload=payload,origin=machine.key,network=machine.network,
            timestamp=os.epoch("utc")
        })
    end
    function self:publish()
        local frame,err=snapshot.frame(app:descriptor(),machine.key,machine.network)
        if not frame then return false,err end
        return self:send(data,frame)
    end
    function self:handle(channel,message)
        if channel==data and type(app.snapshotListeners)=="table" and #app.snapshotListeners>0 then
            if type(message)~="table" or message.machine==machine.key then
                return false
            end
            if message.type~="attacc.sdk.snapshot.v1"
                or message.network~=machine.network
                or type(message.module)~="string" or type(message.descriptor)~="table"
                or message.descriptor.schema~="attacc.sdk.app.v1"
                or message.descriptor.id~=message.module
                or type(message.timestamp)~="number"
                or math.abs(os.epoch("utc")-message.timestamp)>30000 then return false end
            -- Signed commands use separate control/ACK channels.
            -- Legacy telemetry signatures are ignored; never grant access here.
            local stamp=os.epoch("utc")
            sweepReplay(stamp)
            local fingerprint=message.machine..":"..message.module..":"..tostring(message.timestamp)
            if recentSnapshots[fingerprint] then return false end
            recentSnapshots[fingerprint]=stamp
            return app:receiveSnapshot(message)
        end
        if channel==events then
            if type(message)~="table" or message.origin==machine.key then return false end
            if message.type~="attacc.sdk.event.v1" or message.network~=machine.network
                or type(message.origin)~="string" or type(message.topic)~="string"
                or type(message.payload)~="table" or type(message.timestamp)~="number"
                or math.abs(os.epoch("utc")-message.timestamp)>30000 then return false end
            -- LAN events, including node.status, never require authentication.
            return app:receiveNetwork(message)
        end
        if channel~=control then return false end
        local reply=dispatcher:handle(message)
        if reply then
            local sent,err=self:send(ack,reply)
            if not sent then return false,err end
            if reply.ok==true and reply.auth and reply.auth.signature
                and app._sdkAfterAck and #app._sdkAfterAck>0 then
                os.queueEvent("attacc_sdk_after_ack")
            else
                app._sdkAfterAck=nil
            end
            return true
        end
        return false
    end
    return self
end
return M
