-- Generic SDK host: owns the CraftOS loop for standalone SDK applications.
-- Future network/HID drivers are attached here, never in application main.lua.
local M={}
function M.run(app,options)
    options=options or {}
    if type(options.storageService)=="table" then
        require("lib.sdk_storage").install(app,options.storageService)
    end
    -- Every SDK application exposes the same native administration controls.
    -- All remote actions remain disabled unless explicitly configured.
    local policy,policyError=require("lib.sdk_system_config").load()
    if not policy then
        app:log("error",tostring(policyError))
        -- Malformed machine policy never inherits application permissions.
        policy={admin={enabled=false,actions={}}}
    end
    require("lib.sdk_node_admin").install(app,{
        enabled=policy.admin.enabled,
        actions=policy.admin.actions
    })

    local ready,missing=app:checkDependencies()
    if not ready then return false,"missing dependencies: "..table.concat(missing,", ") end
    local status,hardwareReady=app:hardwareStatus()
    if not hardwareReady then
        local missingRoles={}
        for _,role in ipairs(status) do
            if role.required and role.status~="OK" then missingRoles[#missingRoles+1]=role.id end
        end
        return false,"missing hardware: "..table.concat(missingRoles,", ")
    end
    -- Register discovery before the transport opens its SDK event subscription.
    if options.discoverNodes==true then
        app:onNetwork("node.status",function(payload,frame)
            if app.nodeDiscovery and type(payload)=="table"
                and frame.network==payload.network then
                app.nodeDiscovery:accept(payload,frame.origin)
            end
        end)
    end
    local transport
    if options.network~=false then
        local service,transportError=require("lib.sdk_transport").new(app,options)
        if service then transport=service;app.networkTransport=service
        elseif options.networkRequired then return false,transportError end
    end
    local remote
    if transport and options.remoteClient==true then
        transport:subscribeAck()
        remote=require("lib.sdk_remote").new(app,transport,options.remoteOptions)
        app.remoteClient=remote
    end
    if remote and type(options.webCommands)=="table" then
        app.webCommandGate=require("lib.sdk_web_commands").new(app,options.webCommands)
    end
    local discovery
    if transport and options.discoverNodes==true then
        discovery=require("lib.sdk_nodes").new(transport.machine,options.nodeOptions)
        app.nodeDiscovery=discovery
    end
    local lastNodePublish=0
    local lastSystemPublish=0
    local bootAt=os.epoch("utc")
    -- Automatically announce compact host information for every SDK application.
    -- Fast heartbeats stay light; the full inventory is refreshed every 15s.
    local function systemForAnnouncement(now)
        if lastSystemPublish~=0 and now-lastSystemPublish<15000 then return nil end
        lastSystemPublish=now
        local ok,snapshot=pcall(function()
            return require("lib.system_snapshot").compact(app.id)
        end)
        if not ok or type(snapshot)~="table" then
            app:log("warning","system inventory: "..tostring(snapshot))
            return nil
        end
        return snapshot
    end
    local function runtimeStatuses()
        local out={}
        local entries=require("lib.runtime").snapshot().entries or {}
        local count=0
        for key,entry in pairs(entries) do
            if type(entry)=="table" and count<24 then
                out[key]={status=entry.status}
                count=count+1
            end
        end
        return out
    end
    local function announceNode()
        if not transport or options.announceNode==false then return end
        local timestamp=os.epoch("utc")
        if timestamp-lastNodePublish<2000 then return end
        lastNodePublish=timestamp
        local machine=transport.machine
        local machineState=systemForAnnouncement(timestamp)
        local ok,err=app:publishNetwork("node.status",{
            type="attacc.sdk.node.v1",key=machine.key,
            network=machine.network,role=machine.role,preset=machine.preset,
            computerId=machine.computerId,hostname=machine.hostname,
            name=machine.name,label=machine.label,
            apps=machine.apps or {},modules=machine.modules or {},
            capabilities=machine.capabilities or {},tags=machine.tags or {},
            physicalIdentity=machine.physicalIdentity,
            uptimeSeconds=math.floor((timestamp-bootAt)/1000),
            runtime=runtimeStatuses(),system=machineState,
            timestamp=timestamp
        })
        if not ok then app:log("warning","node announcement: "..tostring(err)) end
    end
    local eventListeners={}
    for _,subscription in ipairs(options.eventChannels or {}) do
        if type(subscription)=="number" then
            if transport then transport.modem.open(subscription) end
            eventListeners[subscription]=true
        end
    end
    local socket
    if type(options.websocket)=="table" then
        socket=require("lib.sdk_websocket").new({url=options.websocket.url,token=options.websocket.token,retrySeconds=options.websocket.retrySeconds,allowInsecure=options.websocket.allowInsecure,onState=options.websocket.onState,onMessage=function(message) app:receiveWebMessage(message) end})
        app.webTransport=socket
        socket:connect()
    end
    if type(options.start)=="function" then
        local started,readyOrErr,detail=pcall(options.start,app)
        if not started then return false,"startup failed: "..tostring(readyOrErr) end
        if readyOrErr==false then return false,"startup rejected: "..tostring(detail) end
    end
    -- Headless helpers can publish SDK snapshots without competing for
    -- the shared local display/JSON cache of another app on the same CC.
    if options.publishLocal~=false then
        local published,err=app:publish()
        if not published then return false,err end
    end
    app:status("active","SDK application running")
    local interval=tonumber(options.interval) or 1
    if interval<0.05 then interval=0.05 end
    local running=true
    local timer=os.startTimer(interval)
    -- The built-in CC terminal is strictly text-only to preserve multishell tabs.
    -- Independent external monitors may use CC:Graphics.
    local render=options.display~=false
    local hid=require("lib.sdk_hid").new(app,options)
    local terminal=term.current()
    if options.terminalAppView~=true and type(terminal.setGraphicsMode)=="function" then
        pcall(terminal.setGraphicsMode,false)
    end
    local monitor,monitorName
    local lastTextScale
    local function chooseMonitor()
        if type(options.monitorName)=="string" and options.monitorName~="" then
            if peripheral.isPresent(options.monitorName)
                and peripheral.hasType(options.monitorName,"monitor") then
                return peripheral.wrap(options.monitorName),options.monitorName
            end
            return nil,nil
        end
        local names={}
        for _,name in ipairs(peripheral.getNames()) do
            if peripheral.hasType(name,"monitor") then names[#names+1]=name end
        end
        table.sort(names)
        if #names==0 then return nil,nil end
        return peripheral.wrap(names[1]),names[1]
    end
    local function redraw()
        if not render then return end
        -- Always render the application into its shell tab as text.
        local ok,result=pcall(function()
            if options.terminalAppView==true then
                return app:draw(terminal,{backend=options.terminalMode or "auto"})
            end
            return app:drawMaintenance(terminal)
        end)
        if ok and result and result.ok then
            hid:setRender(result,options.terminalAppView==true and "app" or "maintenance")
        else app:log("warning","SDK terminal display unavailable: "..tostring(result)) end
        local found,name=chooseMonitor()
        if name~=monitorName then
            monitor,monitorName=found,name
            hid:setMonitor(name)
            lastTextScale=nil
        else
            monitor=found
        end
        if monitor then
            local scale=tonumber(options.monitorTextScale)
            if scale and type(monitor.setTextScale)=="function" then
                scale=math.max(0.5,math.min(5,math.floor(scale*2+0.5)/2))
                if lastTextScale~=scale then
                    local scaled,scaleErr=pcall(monitor.setTextScale,scale)
                    if scaled then lastTextScale=scale
                    else app:log("warning","monitor text scale failed: "..tostring(scaleErr)) end
                end
            end
            local drawn,external=pcall(function()
                return app:draw(monitor,{backend=options.monitorMode or "auto"})
            end)
            if drawn and external and external.ok then
                hid:setRender(external,"monitor")
            else
                app:log("warning","SDK monitor display unavailable: "..tostring(external))
            end
        end
    end
    redraw()
    local function dispatch(name,...)
        local handlers=options.handlers or {}
        local fn=handlers[name]
        if type(fn)=="function" then
            local ok,result=pcall(fn,app,...)
            if not ok then app:log("error","event "..name..": "..tostring(result)) end
        end
    end
    local ok,issue=xpcall(function()
        while running do
            local e={os.pullEventRaw()}
            local name=e[1]
            if socket then socket:handle(name,e[2],e[3],e[4]) end
            if name=="attacc_sdk_after_ack" then
                local tasks=app._sdkAfterAck or {}
                app._sdkAfterAck=nil
                for _,task in ipairs(tasks) do
                    local done,err=pcall(task)
                    if not done then app:log("error","after ACK: "..tostring(err)) end
                end
            elseif name=="terminate" then running=false
            elseif name=="timer" and e[2]==timer then
                app:tick()
                if type(options.update)=="function" then
                    local updateOk,updateError=pcall(options.update,app)
                    if not updateOk then error("application update failed: "..tostring(updateError)) end
                end
                dispatch("tick")
                if options.publishLocal~=false then
                    local success,pubErr=app:publish()
                    if not success then app:log("warning","publish failed: "..tostring(pubErr)) end
                end
                if remote then remote:tick() end
                if app.webCommandGate then app.webCommandGate:tick() end
                if transport then
                    announceNode()
                    local sent,sendErr=transport:publish()
                    if not sent then app:log("warning","network snapshot: "..tostring(sendErr)) end
                end
                redraw()
                timer=os.startTimer(interval)
            elseif name=="modem_message" then
                if transport then transport:handle(e[3],e[5]) end
                if remote then remote:handle(e[3],e[5]) end
                if eventListeners[e[3]] and type(options.onNetworkEvent)=="function" then
                    local callOk,callErr=pcall(options.onNetworkEvent,app,e[3],e[5])
                    if not callOk then app:log("error","network event: "..tostring(callErr)) end
                end
                dispatch(name,table.unpack(e,2))
            elseif name=="monitor_touch" or name=="mouse_click" or name=="key" then
                local handled,touchResult=pcall(function()
                    return {hid:handle(name,table.unpack(e,2))}
                end)
                local touched=false
                if handled then
                    touched=touchResult[1]==true
                    if name=="monitor_touch" then
                        local diagnostic=touched and "accepted" or tostring(touchResult[2] or "no hit")
                        app:log(touched and "info" or "warning",
                            "monitor_touch "..tostring(e[2])..
                            " x="..tostring(e[3]).." y="..tostring(e[4])..
                            " selected="..tostring(monitorName).." -> "..diagnostic)
                    end
                else
                    app:log("error","SDK HID: "..tostring(touchResult))
                end
                if touched then redraw() end
                dispatch(name,table.unpack(e,2))
            elseif name=="peripheral" or name=="peripheral_detach" or name=="monitor_resize" then
                redraw()
                dispatch(name,table.unpack(e,2))
            else dispatch(name,table.unpack(e,2)) end
        end
    end,function(e) return tostring(e) end)
    if socket then socket:close() end
    app:close()
    if not ok then return false,issue end
    return true
end
return M
