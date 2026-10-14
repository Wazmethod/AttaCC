local config = require("lib.config")
local protocol = require("lib.protocol")
local displayCore = require("lib.display")
local display = require("lib.dashboard_display")
local nodes = require("lib.nodes")
local network = require("lib.network")
local runtime = require("lib.runtime")

local modem=protocol.findWirelessModem()
if not modem then error("Wireless modem introuvable") end

local nodeBus=nodes.new(modem,"dashboard")
local net=network.new(config,nodeBus.machine)

local monitor,monitorName=nil,nil
local displayWidth,displayHeight=nil,nil
local page="home"
local machineTab="data"
local machinePage=1
local selectedAppKey=nil
local apps={}
local events={}
local pending=nil
local seq=1

local function appKey(msg)
    local app=msg and msg.ui and msg.ui.app
    if type(app)~="table" then return nil end
    return tostring(msg.network or nodeBus.machine.network)..":"
        ..tostring(app.machine or msg.machine)..":"
        ..tostring(app.module or msg.module)
end

local function graphs(msg)
    return msg and msg.ui and type(msg.ui.graphs)=="table" and msg.ui.graphs or {}
end

local function remember(msg)
    local key=appKey(msg)
    if not key then return end
    local old=apps[key] or {}
    local history=old.history or {}
    local ts=msg.timestamp or protocol.now()
    for _,g in ipairs(graphs(msg)) do
        local id=tostring(g.id or g.label or "value")
        local value=tonumber(g.value)
        if value~=nil then
            local bucket=history[id] or {}
            local last=bucket[#bucket]
            if not last or last.timestamp~=ts then
                table.insert(bucket,{timestamp=ts,value=value,label=g.label or id,unit=g.unit})
                while #bucket>((config.dashboard and config.dashboard.historySamples) or 120) do
                    table.remove(bucket,1)
                end
            end
            history[id]=bucket
        end
    end
    local app=msg.ui.app
    apps[key]={
        key=key,network=msg.network or nodeBus.machine.network,
        machine=app.machine or msg.machine,machineLabel=app.machineLabel,
        module=app.module or msg.module,title=app.title or msg.ui.title or msg.module,
        data=msg,seenAt=protocol.now(),history=history,
    }
    if not selectedAppKey then selectedAppKey=key end
end

local function listApps()
    local out={}
    local now=protocol.now()
    for key,item in pairs(apps) do
        table.insert(out,{
            key=key,network=item.network,machine=item.machine,machineLabel=item.machineLabel,
            module=item.module,title=item.title,data=item.data,history=item.history,
            fresh=(now-item.seenAt)<config.timing.sourceStaleMs,ageMs=now-item.seenAt,
        })
    end
    table.sort(out,function(a,b)
        return tostring(a.machineLabel or a.machine or a.key)<tostring(b.machineLabel or b.machine or b.key)
    end)
    return out
end

local function selectApp(key)
    if apps[key] then
        selectedAppKey=key
        machineTab="data"
        machinePage=1
        return true
    end
    return false
end

local function hostname(machineKey)
    for _,n in ipairs(nodeBus:list()) do
        if n.key==machineKey then return n.hostname or n.label or n.key end
    end
    return machineKey or "unknown"
end

local function pushEvent(e)
    e=e or {}
    e.hostname=e.hostname or hostname(e.machine or e.source)
    table.insert(events,1,e)
    while #events>(config.events.historySize or 80) do table.remove(events) end
end

local function refreshDisplay(force)
    local mon,nameOrErr=displayCore.find("auto")
    if not mon then
        if monitor then pcall(display.shutdown,monitor) end
        monitor,monitorName=nil,nil
        runtime.set("module:core.display","inactive",{detail=tostring(nameOrErr or "no monitor")})
        return false
    end
    local w,h=displayCore.geometry(mon)
    if monitor==mon and displayWidth==w and displayHeight==h and not force then return true end
    monitor,monitorName,displayWidth,displayHeight=mon,nameOrErr,w,h
    local ok,status=pcall(display.init,mon)
    if not ok then
        runtime.set("module:core.display","degraded",{detail=tostring(status)})
        return false
    end
    runtime.set("module:core.display","active",{
        device=monitorName,width=w,height=h,backend=status.backend,detail="dashboard display active"
    })
    return true
end

local function state()
    return {
        page=page,machineTab=machineTab,machinePage=machinePage,
        selectedAppKey=selectedAppKey,apps=listApps(),events=events,nodes=nodeBus:list(),
        pending=pending,now=protocol.now(),home=config.dashboard and config.dashboard.home or {},
        storage={available=false,error="not hosted by dashboard"},
        web={status="disabled",detail="not hosted by dashboard"},
        display={state=monitor and "active" or "inactive",name=monitorName,width=displayWidth,height=displayHeight,
            backend=monitor and display.getStatus().backend or nil},
    }
end

local function redraw()
    if monitor then pcall(display.draw,monitor,state()) end
end

local function id()
    local value="dashboard-"..tostring(os.getComputerID()).."-"..tostring(protocol.now()).."-"..tostring(seq)
    seq=seq+1
    return value
end

local function transmit()
    if not pending then return end
    protocol.send(modem,config.channels.control,pending.message)
    pending.sentAt=protocol.now()
    pending.retries=pending.retries+1
end

local function send(control)
    local app=selectedAppKey and apps[selectedAppKey] or nil
    if not app or pending then return end
    local command=type(control)=="table" and control.command or control
    if not command then return end
    local args={}
    if type(control)=="table" and type(control.args)=="table" then
        for k,v in pairs(control.args) do args[k]=v end
    end
    if type(control)=="table" and control.rpm~=nil then args.rpm=control.rpm end
    local requestId=id()
    pending={
        id=requestId,command=command,sentAt=0,retries=0,
        message=protocol.makeModuleCommand(app.module,command,"dashboard",requestId,args,app.machine),
    }
    transmit()
end

runtime.set("app:dashboard","active",{detail="AttaCC display dashboard active"})
modem.open(config.channels.telemetry)
modem.open(config.channels.events)
modem.open(config.channels.ack)
if config.channels.moduleData then modem.open(config.channels.moduleData) end
if config.channels.moduleEvents then modem.open(config.channels.moduleEvents) end
if config.channels.moduleAck then modem.open(config.channels.moduleAck) end

refreshDisplay(true)
redraw()

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(2,2)
print("ATTACC DASHBOARD")
print("")
print("Display : "..tostring(monitorName or "none"))
print("Network : "..tostring(nodeBus.machine.network))
print("Use the attached monitor for control.")

local timer=os.startTimer(config.timing.refreshSeconds)

while true do
    local event,p1,p2,p3,p4=os.pullEvent()

    if event=="modem_message" then
        local channel,msg=p2,p4
        if net then net:handle(channel,p3,msg) end
        local nodeAction=nodeBus:handle(channel,msg)
        if nodeAction=="reboot" then sleep(.15); os.reboot() end

        if (channel==config.channels.telemetry or channel==config.channels.moduleData)
            and type(msg)=="table"
            and (not msg.network or msg.network==nodeBus.machine.network)
        then remember(msg)
        elseif (channel==config.channels.events or channel==config.channels.moduleEvents)
            and type(msg)=="table"
            and (not msg.network or msg.network==nodeBus.machine.network)
        then pushEvent(msg)
        elseif (channel==config.channels.ack or channel==config.channels.moduleAck)
            and type(msg)=="table" and pending and msg.id==pending.id
        then pending=nil end

    elseif event=="monitor_touch" and monitor and (not monitorName or p1==monitorName) then
        local action,arg=display.actionAt(p2,p3)
        if action=="page" then page=arg
        elseif action=="machine_select" then selectApp(arg); page="machine"
        elseif action=="machine_tab" then machineTab=arg; machinePage=1
        elseif action=="machine_page" then machinePage=tonumber(arg) or 1
        elseif action=="event_machine" and arg then
            for key,item in pairs(apps) do
                if item.machine==arg then selectApp(key); page="machine"; break end
            end
        elseif action=="command" then send(arg)
        elseif action=="node_reboot" and arg then
            local _,_,localTarget=nodeBus:sendReboot({arg},"dashboard",id())
            if localTarget then sleep(.15); os.reboot() end
        end
        redraw()

    elseif event=="peripheral" or event=="peripheral_detach" or event=="monitor_resize" then
        refreshDisplay(true); redraw()

    elseif event=="timer" and p1==timer then
        nodeBus:tick()
        refreshDisplay(false)
        if pending and protocol.now()-pending.sentAt>=config.timing.commandRetryMs then
            if pending.retries<config.timing.commandMaxRetries then transmit()
            else pushEvent({level="critical",code="NO_ACK",message="No ACK for "..tostring(pending.command),
                timestamp=protocol.now(),machine=nodeBus.machine.key}); pending=nil end
        end
        redraw()
        timer=os.startTimer(config.timing.refreshSeconds)
    end
end
