-- SDK-native WebBridge: SDK envelopes only, no legacy adapter.
-- Commands/admin are deliberately unavailable until SDK authorization parity.
local attacc=require("lib.attacc")
local app=attacc.app("webbridge_preview",{title="WebBridge SDK Preview"})
app:config({bridge={url="",token="",heartbeatSeconds=2,allowRemoteCommands=false,allowedApps={}}})
app:require("core.runtime")
app:require("module.network")
local machine=require("lib.machine").get(app.id)
local url,token=app:config("bridge.url",""),app:config("bridge.token","")
local seen={}
local stats={snapshots=0,telemetry=0,events=0,nodes=0,commands=0}
for _,v in ipairs({"connection","snapshots","telemetry","events","nodes","commands"}) do
    app:data(v,{label=v})
end
app:view("home",{label="HOME",layout="widgets",widgets={
    {type="data",id="connection"},{type="data",id="snapshots"},
    {type="data",id="telemetry"},{type="data",id="events"},
    {type="data",id="nodes"},{type="data",id="commands"}
}})
local function emit(frame)
    if not frame then return false end
    local id=table.concat({frame.type or "",frame.network or "",frame.machine or frame.key or "",
        frame.module or "",tostring(frame.timestamp or "")},":")
    local now=os.epoch("utc")
    if seen[id] and now-seen[id]<3000 then return false end
    seen[id]=now
    return app:webSend(frame)
end
app:onSnapshot(function(frame)
    if emit(frame) then stats.snapshots=stats.snapshots+1 end
end)
app:onNetwork("app.event",function(payload,frame)
    if emit(frame) then stats.events=stats.events+1 end
end)
-- Incoming Web control requests use the SDK command client, never modem APIs.
-- The Web server must be trusted separately; remote execution is opt-in.
local inFlight={}
app:onWebMessage(function(message)
    if message.type~="attacc.sdk.web.command.v1" then return end
    local id=message.id
    local function reject(reason)
        if type(id)=="string" and #id>0 and #id<=128 then
            app:webSend({type="attacc.sdk.web.ack.v1",id=id,ok=false,
                error=reason,timestamp=os.epoch("utc")})
        end
    end
    if app:config("bridge.allowRemoteCommands",false)~=true then
        reject("remote commands disabled");return
    end
    if type(id)~="string" or #id<1 or #id>128
        or not id:match("^[%w_.%-]+$") then return end
    if inFlight[id] then reject("duplicate request");return end
    if type(message.target)~="string" or #message.target<1 or #message.target>128
        or type(message.app)~="string" or #message.app<1 or #message.app>64
        or type(message.control)~="string" or #message.control<1
        or #message.control>64 or type(message.args)~="table" then
        reject("invalid command");return
    end
    local allowed=app:config("bridge.allowedApps",{})
    if type(allowed)~="table" or allowed[message.app]~=true then
        reject("application not permitted");return
    end
    if type(message.timestamp)~="number"
        or math.abs(os.epoch("utc")-message.timestamp)>10000 then
        reject("expired request");return
    end
    if not app.remoteClient then reject("SDK command client unavailable");return end
    inFlight[id]=true
    local ok,err=app:remoteCommand(message.target,message.app,message.control,
        message.args,function(success,reason,_,ack)
            inFlight[id]=nil
            app:webSend({type="attacc.sdk.web.ack.v1",id=id,ok=success,
                error=reason,commandId=ack and ack.id,
                timestamp=os.epoch("utc")})
        end)
    if not ok then inFlight[id]=nil;reject(tostring(err))
    else stats.commands=stats.commands+1 end
end)
local lastHeartbeat=0
local function heartbeat()
    local now=os.epoch("utc")
    if now-lastHeartbeat<2000 then return end
    lastHeartbeat=now
    local snapshot=require("lib.runtime").snapshot()
    emit({type="attacc.sdk.node.v1",key=machine.key,role=machine.role,
        preset=machine.preset,computerId=machine.computerId,
        hostname=machine.hostname,name=machine.name,label=machine.label,
        apps=machine.apps or {},modules=machine.modules,tags=machine.tags,
        capabilities=machine.capabilities or {},network=machine.network,
        runtime=snapshot.entries or {},physicalIdentity=machine.physicalIdentity,
        timestamp=now})
end
app:lifecycle({network=true,networkRequired=true,remoteClient=true,display=true,interval=1,
    websocket={url=url,token=token,
        onState=function(state)
            app:set("connection",state)
        end,
        -- Inbound WebSocket frames dispatch through app:onWebMessage().
    },
    update=function()
        heartbeat()
        for k,v in pairs(stats) do app:set(k,v) end
        app:set("connection",app:webStatus())
        local t=os.epoch("utc")
        for id,at in pairs(seen) do if t-at>10000 then seen[id]=nil end end
    end})
return app
