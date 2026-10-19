-- Master V1.1 SDK-native application. Receives typed SDK snapshots.
-- Remote hardware commands remain disabled by default.
local attacc=require("lib.attacc")
local app=attacc.app("master",{title="AttaCC Master SDK"})
app:config({display={viewMode="views",mode="auto",textScale=0.5},
    supervision={staleMs=12000,allowRemoteCommands=true}})
app:require("core.runtime")
app:require("module.network")
app:require("module.display")

local peers={}
local events={}
local limit=100
local histories={}
local services=require("lib.sdk_services")
local graphHistory=require("lib.sdk_graph_history")
local controlPage=1
local metricPage=1
local graphPage=1
local machinePage=1
local restored=app:state("events")
if type(restored)=="table" and type(restored.entries)=="table" then
    for _,entry in ipairs(restored.entries) do
        if type(entry)=="string" and #entry<=160 then
            events[#events+1]=entry
            if #events>=limit then break end
        end
    end
end
local eventsDirty=false
local lastEventSave=0
local function now() return os.epoch("utc") end
-- The same categories power the in-game SDK and web DATA groups.
local dataCategories={
    online="SUPERVISION",total="SUPERVISION",stale="SUPERVISION",
    selected="SOURCE",source_label="SOURCE",machine="SOURCE",
    network="SOURCE",age="SOURCE",metrics="SOURCE",
    controls="SOURCE",status="SOURCE",
    nodes="NETWORK",nodes_online="NETWORK",conflicts="NETWORK",
    storage_status="SERVICES",web_status="SERVICES",
    recent_event="EVENTS",event_count="EVENTS",
    event_1="EVENTS",event_2="EVENTS",event_3="EVENTS",
    metric_1="REMOTE DATA",metric_2="REMOTE DATA",metric_3="REMOTE DATA",
    command_status="REMOTE CONTROLS",
    control_1="REMOTE CONTROLS",control_2="REMOTE CONTROLS",control_3="REMOTE CONTROLS",
    control_page="NAVIGATION",metric_page="NAVIGATION",graph_page="NAVIGATION",
    uptime="SYSTEM",
    machine_1="MACHINES",machine_2="MACHINES",machine_3="MACHINES"
}
for _,field in ipairs({
    {"online","Online applications"},{"total","Known applications"},
    {"stale","Stale applications"},{"selected","Selected application"},
    {"source_label","Selected source"},
    {"machine","Machine"},{"network","Network"},
    {"age","Snapshot age","s"},{"metrics","Exported metrics"},
    {"controls","Remote controls"},{"status","Application status"},
    {"nodes","Known nodes"},{"nodes_online","Nodes online"},
    {"conflicts","Identity conflicts"},
    {"storage_status","Storage"},{"web_status","WebBridge"},
    {"recent_event","Recent event"},{"metric_1","Metric 1"},
    {"metric_2","Metric 2"},{"metric_3","Metric 3"},
    {"event_count","Event count"},{"event_1","Recent event"},
    {"event_2","Previous event"},{"event_3","Earlier event"},
    {"command_status","Command status"},{"control_1","Control 1"},
    {"control_2","Control 2"},{"control_3","Control 3"},
    {"control_page","Control page"},{"metric_page","Metric page"},
    {"graph_page","Graph page"},{"uptime","Uptime"},
    {"machine_1","Machine 1"},{"machine_2","Machine 2"},{"machine_3","Machine 3"}
}) do app:data(field[1],{label=field[2],unit=field[3],category=dataCategories[field[1]] or "SYSTEM"}) end

-- Preserve the historical HOME / MACHINE / EVENTS / NETWORK navigation.
-- The historical MACHINE page has DATA / GRAPHS / CONTROLS tabs.
local function cards(items)
    local out={}
    for _,id in ipairs(items) do out[#out+1]={type="data",id=id} end
    return out
end
app:view("home",{label="HOME",layout="widgets",columns=2,cardHeight=83,widgets={
    {type="group",label="SUPERVISION",items={"online","nodes_online","status"}},
    {type="group",label="SERVICES",items={"storage_status","web_status"}},
    {type="group",label="ACTIVITY",items={"recent_event"}}}})
app:view("machine",{label="MACHINE",layout="widgets",columns=1,cardHeight=35,
    dynamicRows=true,sourceNavigation={titleOnly=true,data="selected"},
    navigation={previous="previous_machine_page",next="next_machine_page"},widgets={
        {type="machine-row",id="machine_1",select="select_machine_1",reboot="reboot_machine_1"},
        {type="machine-row",id="machine_2",select="select_machine_2",reboot="reboot_machine_2"},
        {type="machine-row",id="machine_3",select="select_machine_3",reboot="reboot_machine_3"}
}})
app:view("machine_data",{parent="machine",label="DATA",layout="widgets",
    columns=2,cardHeight=83,exportGroups="data",widgets={
        {type="group",label="SOURCE",items={"selected","machine","status","age"}}
}})
app:view("machine_graphs",{parent="machine",label="GRAPHS",layout="widgets",
    columns=2,exportGroups="graphs",widgets={}})
app:view("machine_controls",{parent="machine",label="CONTROLS",layout="widgets",
    columns=2,cardHeight=83,exportGroups="controls",widgets={}})
app:view("events",{label="EVENTS",layout="widgets",columns=2,cardHeight=83,widgets={
    {type="group",label="EVENT LOG",items={"event_count","event_1","event_2","event_3"}}}})
app:view("network",{label="NETWORK",layout="widgets",columns=2,cardHeight=83,widgets={
    {type="group",label="NODES",items={"nodes","nodes_online","conflicts"}},
    {type="group",label="APPLICATIONS",items={"total","stale","network"}}}})

local selectedKey=nil
local selectedMachine=nil
local function machines()
    local names,seen={},{}
    local me=app.networkTransport and app.networkTransport.machine.key
    local function add(key)
        if type(key)=="string" and key~="" and not seen[key] then
            seen[key]=true;names[#names+1]=key
        end
    end
    add(me)
    for _,node in ipairs(app:nodes()) do add(node.key) end
    for _,peer in pairs(peers) do add(peer.machine) end
    table.sort(names,function(x,y)
        if x==me then return true end
        if y==me then return false end
        return x<y
    end)
    return names
end
local function selectMachine(machine)
    selectedMachine=machine
    selectedKey=nil
    local keys={}
    for key,peer in pairs(peers) do
        if peer.machine==machine then keys[#keys+1]=key end
    end
    table.sort(keys)
    selectedKey=keys[1]
    metricPage,graphPage,controlPage=1,1,1
    app.displayPage=1
    app.monitorPendingControl=nil
end
local function key(frame)
    return frame.network..":"..frame.machine..":"..frame.descriptor.id
end
app:onSnapshot(function(frame)
    local d=frame.descriptor
    if type(d.id)~="string" or #d.id>64
        or type(d.data)~="table" or type(d.controls)~="table" then return end
    local k=key(frame)
    local previous=peers[k]
    local warnings=d.exportWarnings
    local truncated=type(warnings)=="table"
        and type(warnings.truncated)=="table" and next(warnings.truncated)~=nil
    if truncated and not (previous and previous.truncated) then
        app:toast("SOURCE EXPORTS TRUNCATED: "..d.id,"warning")
    end
    peers[k]={truncated=truncated,key=k,network=frame.network,machine=frame.machine,
        id=d.id,title=d.title or d.id,seen=now(),
        data=d.data,graphs=d.graphs or {},controls=d.controls}
    histories[k]=graphHistory.ingest(histories[k],d.graphs,now())
    if not selectedMachine then selectedMachine=frame.machine end
    if selectedMachine==frame.machine and not selectedKey then selectedKey=k end
end)

local function ordered()
    local result={}
    for _,peer in pairs(peers) do result[#result+1]=peer end
    table.sort(result,function(a,b) return a.key<b.key end)
    return result
end
for slot=1,3 do
    local i=slot
    app:control("select_machine_"..i,{label="SELECT",remote=false,
        monitor=true,navigation=true,
        enabled=function()
            local machine=machines()[(machinePage-1)*3+i]
            local me=app.networkTransport and app.networkTransport.machine.key
            return machine~=nil and machine~=me
        end,
        run=function()
            local machine=machines()[(machinePage-1)*3+i]
            if not machine then return false,"no machine" end
            if machine==(app.networkTransport and app.networkTransport.machine.key) then
                return false,"select another machine"
            end
            selectMachine(machine)
            return app:showView("machine_data")
        end})
end
-- Machine reboot is opt-in, signed and double-confirmed by the SDK display.
for slot=1,3 do
    local i=slot
    local function target()
        return machines()[(machinePage-1)*3+i]
    end
    local function rebootReady()
        local machine=target()
        if not machine then return false end
        local me=app.networkTransport and app.networkTransport.machine.key
        if machine==me then return true end
        if not remoteAllowed then return false end
        local policy=require("lib.sdk_auth").load()
        local client=policy and policy.client
        if not (app:config("supervision.allowRemoteCommands",false)==true
            and app.remoteClient and client and client.enabled==true
            and client.origin==me and type(client.secret)=="string"
            and #client.secret>=32) then return false end
        local stale=tonumber(app:config("supervision.staleMs",12000)) or 12000
        for _,peer in pairs(peers) do
            if peer.machine==machine and now()-peer.seen<=stale then
                for _,control in ipairs(peer.controls or {}) do
                    if control.id=="node_reboot" and control.remote==true
                        and control.enabled~=false then return true end
                end
            end
        end
        return false
    end
    app:control("reboot_machine_"..i,{label="REBOOT",remote=false,
        monitor=true,confirm=true,enabled=rebootReady,
        run=function()
            local machine=target()
            if not machine or not rebootReady() then return false,"reboot locked" end
            local me=app.networkTransport and app.networkTransport.machine.key
            if machine==me then
                os.queueEvent("attacc_master_self_reboot")
                return true
            end
            local stale=tonumber(app:config("supervision.staleMs",12000)) or 12000
            for _,peer in pairs(peers) do
                if peer.machine==machine and now()-peer.seen<=stale then
                    for _,control in ipairs(peer.controls or {}) do
                        if control.id=="node_reboot" and control.remote==true
                            and control.enabled~=false then
                            commandStatus="PENDING REBOOT "..machine
                            app:toast(commandStatus,"info")
                            local ok,err=app:remoteCommand(machine,peer.id,
                                "node_reboot",{confirm=true},function(success,reason)
                                    commandStatus=success and ("REBOOT ACK "..machine)
                                        or ("ERROR "..tostring(reason))
                                    app:toast(commandStatus,success and "success" or "error")
                                end)
                            if not ok then commandStatus="REJECTED "..tostring(err);app:toast(commandStatus,"error") end
                            return ok,err
                        end
                    end
                end
            end
            return false,"reboot unavailable"
        end})
end
for _,entry in ipairs({
    {id="previous_machine_page",step=-1},
    {id="next_machine_page",step=1},
}) do
    local step=entry.step
    app:control(entry.id,{label=entry.id,remote=false,monitor=true,navigation=true,
        enabled=function() return #machines()>3 end,
        run=function()
            local pages=math.max(1,math.ceil(#machines()/3))
            machinePage=math.max(1,math.min(pages,machinePage+step))
            return true
        end})
end
-- Page the full SDK data and graph exports of the selected source.
for _,spec in ipairs({
    {id="previous_metrics",kind="metrics",delta=-1,size=3},
    {id="next_metrics",kind="metrics",delta=1,size=3},
    {id="previous_graphs",kind="graphs",delta=-1,size=2},
    {id="next_graphs",kind="graphs",delta=1,size=2}
}) do
    local kind,delta,size=spec.kind,spec.delta,spec.size
    app:control(spec.id,{label=spec.id,remote=false,monitor=true,navigation=true,
        run=function()
            local peer=peers[selectedKey]
            local total=peer and #(kind=="metrics" and peer.data or peer.graphs) or 0
            local pages=math.max(1,math.ceil(total/size))
            if kind=="metrics" then
                metricPage=((metricPage-1+delta+pages)%pages)+1
            else
                graphPage=((graphPage-1+delta+pages)%pages)+1
            end
            return true
        end})
end
-- Remote control slots are application-defined but never inferred from labels.
-- The SDK remote client signs and verifies ACKs; no legacy fallback.
local commandStatus="READ ONLY"
local function exposedControls()
    local peer=peers[selectedKey]
    local result={}
    if not peer then return result end
    for _,control in ipairs(peer.controls or {}) do
        if type(control)=="table" and type(control.id)=="string"
            and control.remote==true and control.enabled~=false
            and control.uiHidden~=true then
            result[#result+1]=control
        end
    end
    return result
end
for _,step in ipairs({{id="previous_controls",step=-1},
                      {id="next_controls",step=1}}) do
    local delta=step.step
    app:control(step.id,{label=step.id,remote=false,monitor=true,navigation=true,
        run=function()
            local pages=math.max(1,math.ceil(#exposedControls()/3))
            controlPage=((controlPage-1+delta+pages)%pages)+1
            app.monitorPendingControl=nil
            return true
        end})
end
-- The renderer owns the exported-button layout, including state-dependent
-- labels and category grouping. Master only signs the selected action.
local function remoteAllowed()
    local policy=require("lib.sdk_auth").load()
    local client=policy and policy.client
    local me=app.networkTransport and app.networkTransport.machine.key
    return app:config("supervision.allowRemoteCommands",false)==true
        and app.remoteClient~=nil and type(client)=="table"
        and client.enabled==true and client.origin==me
        and type(client.secret)=="string" and #client.secret>=32
end
-- Stable graphics export handlers: no numbered proxy controls.
app.remoteDisplayUnavailableReason=function()
    local peer=peers[selectedKey]
    if not peer then return "NO SOURCE SELECTED" end
    local staleMs=tonumber(app:config("supervision.staleMs",12000)) or 12000
    if now()-peer.seen>staleMs then return "SOURCE STALE" end
    if not remoteAllowed() then return "REMOTE CONTROL LOCKED" end
    return "REMOTE CONTROL UNAVAILABLE"
end
app.remoteDisplayReady=function()
    local peer=peers[selectedKey]
    local staleMs=tonumber(app:config("supervision.staleMs",12000)) or 12000
    return remoteAllowed() and peer~=nil and now()-peer.seen<=staleMs
end
app.remoteDisplayIdentity=function()
    local peer=peers[selectedKey]
    return peer and (tostring(peer.network)..":"..tostring(peer.machine)..":"..tostring(peer.id)) or nil
end
app.remoteDisplayHandler=function(controlId,expectedSource)
    local peer=peers[selectedKey]
    if not remoteAllowed() or not peer then return false,"remote controls locked" end
    local identity=tostring(peer.network)..":"..tostring(peer.machine)..":"..tostring(peer.id)
    if identity~=expectedSource then return false,"remote source changed" end
    local staleMs=tonumber(app:config("supervision.staleMs",12000)) or 12000
    if now()-peer.seen>staleMs then return false,"source stale" end
    local command,err=require("lib.sdk_remote_controls").byId(peer.controls,controlId)
    if not command then return false,err end
    commandStatus="PENDING "..command
    app:toast(commandStatus,"info")
    local ok,reason=app:remoteCommand(peer.machine,peer.id,command,{},function(success,detail)
        commandStatus=success and ("ACK "..command) or ("ERROR "..tostring(detail))
        app:toast(commandStatus,success and "success" or "error")
    end)
    if not ok then
        commandStatus="REJECTED "..tostring(reason)
        app:toast(commandStatus,"error")
    end
    return ok,reason
end
app:maintenance("console",{title="Master supervision",
    status={
        {id="online",label="Online",read=function() return app.dataItems.online.value or 0 end},
        {id="total",label="Known",read=function() return app.dataItems.total.value or 0 end},
        {id="selected",label="Selected",read=function() return app.dataItems.selected.value or "--" end},
        {id="status",label="Status",read=function() return app.dataItems.status.value or "--" end}
    },tools={"previous_machine_page","next_machine_page"},logLimit=5})

local function update()
    if eventsDirty and now()-lastEventSave>=30000 then
        local ok,err=app:state("events",{entries=events})
        if ok then eventsDirty=false;lastEventSave=now()
        else app:log("warning","event persistence: "..tostring(err)) end
    end
    local list=ordered()
    local online=0
    local staleAfter=tonumber(app:config("supervision.staleMs",12000)) or 12000
    for _,peer in ipairs(list) do
        if now()-peer.seen<=staleAfter then online=online+1 end
    end
    local peer=peers[selectedKey]
    if not selectedMachine and list[1] then selectMachine(list[1].machine) end
    peer=peers[selectedKey]
    local dataExports={}
    for _,item in ipairs(peer and peer.data or {}) do dataExports[#dataExports+1]=item end
    local selectedNode=selectedMachine and app:node(selectedMachine)
    if selectedNode and selectedNode.uptimeSeconds then
        dataExports[#dataExports+1]={id="node_uptime",label="Uptime",
            category="SYSTEM",value=selectedNode.uptimeSeconds,unit="s"}
    end
    app:setRemoteExports("data",dataExports)
    app:setRemoteExports("graphs",graphHistory.exports(peer and peer.graphs,peer and histories[peer.key]))
    app:setRemoteExports("controls",peer and peer.controls or {})
    local age=peer and math.max(0,now()-peer.seen) or nil
    metricPage=math.min(metricPage,math.max(1,math.ceil(#(peer and peer.data or {})/3)))
    graphPage=math.min(graphPage,math.max(1,math.ceil(#(peer and peer.graphs or {})/2)))
    controlPage=math.min(controlPage,math.max(1,math.ceil(#exposedControls()/3)))
    local nodes=app:nodes()
    local nodesOnline,conflicts=0,0
    for _,node in ipairs(nodes) do
        if node.online then nodesOnline=nodesOnline+1 end
        if node.conflict then conflicts=conflicts+1 end
    end
    local metrics={}
    if peer then
        for _,item in ipairs(peer.data) do
            if type(item)=="table" and item.id then
                metrics[#metrics+1]=tostring(item.label or item.id)..": "..
                    tostring(item.value==nil and "--" or item.value)
            end
        end
    end
    -- The SDK renderer owns graph pagination and the tab page count.
    local values={
        command_status=commandStatus,
        control_page=tostring(controlPage).."/"..tostring(math.max(1,math.ceil(#exposedControls()/3))),
        control_1=(exposedControls()[(controlPage-1)*3+1] or {}).label or "--",
        control_2=(exposedControls()[(controlPage-1)*3+2] or {}).label or "--",
        control_3=(exposedControls()[(controlPage-1)*3+3] or {}).label or "--",
        metric_page=tostring(metricPage).."/"..tostring(math.max(1,math.ceil(#metrics/3))),
        graph_page=tostring(graphPage).."/"..tostring(math.max(1,math.ceil(#(peer and peer.graphs or {})/2))),
        metric_1=metrics[(metricPage-1)*3+1] or "--",
        metric_2=metrics[(metricPage-1)*3+2] or "--",
        metric_3=metrics[(metricPage-1)*3+3] or "--",
        storage_status=(services.status("network.storage") or {}).status or "unknown",
        web_status=(function()
            for _,node in ipairs(app:nodes()) do
                local inventory=type(node.system)=="table" and node.system.apps or {}
                for _,entry in ipairs(inventory) do
                    if (type(entry)=="table" and entry.name=="webbridge") or entry=="webbridge" then
                        return node.online and "ONLINE" or "OFFLINE"
                    end
                end
            end
            return "SEPARATE APP"
        end)(),
        recent_event=events[1] and events[1] or "NO EVENTS",
        event_count=#events,event_1=events[1] or "--",
        event_2=events[2] or "--",event_3=events[3] or "--",
        nodes=#nodes,nodes_online=nodesOnline,conflicts=conflicts,
        total=#list,online=online,stale=#list-online,
        selected=(selectedNode and selectedNode.hostname) or selectedMachine or "NONE",
        source_label=peer and (tostring(peer.machine).." / "..tostring(peer.id)) or "--",
        machine=peer and peer.machine or "--",
        network=peer and peer.network or "--",
        age=age and math.floor(age/1000) or 0,
        metrics=peer and #peer.data or 0,
        controls=peer and #peer.controls or 0,
        uptime=(function()
            local node=selectedMachine and app:node(selectedMachine)
            return node and node.uptimeSeconds and tostring(node.uptimeSeconds).." s" or "--"
        end)(),
        status=not peer and "NO SOURCES" or
            (age<=staleAfter and "ONLINE" or "STALE")}
    local machineList=machines()
    machinePage=math.min(machinePage,math.max(1,math.ceil(#machineList/3)))
    for i=1,3 do
        local machine=machineList[(machinePage-1)*3+i]
        local name=machine and machine or "--"
        if machine then
            local node=app:node(machine)
            if node and node.hostname then name=node.hostname end
            local active=false
            for _,item in ipairs(list) do
                if item.machine==machine and now()-item.seen<=staleAfter then
                    active=true;break
                end
            end
            name=name.." / "..(active and "ONLINE" or "NO APP")
        end
        values["machine_"..i]=name
    end
    for id,value in pairs(values) do app:set(id,value) end

end
app:onNetwork("app.event",function(payload,frame)
    if type(payload)~="table" then return end
    local entry=(tostring(frame.origin or "?").." "..
        tostring(payload.code or "EVENT")..": "..
        tostring(payload.message or "")):sub(1,160)
    table.insert(events,1,entry)
    while #events>limit do table.remove(events) end
    eventsDirty=true
end)
app:lifecycle({interval=1,network=true,networkRequired=true,remoteClient=true,discoverNodes=true,display=true,
    monitorTextScale=app:config("display.textScale",0.5),
    monitorMode=app:config("display.mode","auto"),
    start=update,update=update,
    handlers={attacc_master_self_reboot=function() os.reboot() end}})
return app
