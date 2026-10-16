-- Master V1.1 SDK-native application. Receives typed SDK snapshots.
-- Remote hardware commands remain disabled by default.
local attacc=require("lib.attacc")
local app=attacc.app("master",{title="AttaCC Master SDK"})
app:config({display={viewMode="views",mode="auto",textScale=0.5},
    supervision={staleMs=12000,allowRemoteCommands=false}})
app:require("core.runtime")
app:require("module.network")
app:require("module.display")

local peers={}
local events={}
local limit=100
local histories={}
local services=require("lib.sdk_services")
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
app:graph("master_graph_1",{label="Remote metric 1",limit=120})
app:graph("master_graph_2",{label="Remote metric 2",limit=120})
local function now() return os.epoch("utc") end
for _,field in ipairs({
    {"online","Online applications"},{"total","Known applications"},
    {"stale","Stale applications"},{"selected","Selected application"},
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
    {"graph_page","Graph page"},
    {"machine_1","Machine 1"},{"machine_2","Machine 2"},{"machine_3","Machine 3"}
}) do app:data(field[1],{label=field[2],unit=field[3]}) end

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
        {type="machine-row",id="machine_1",select="select_machine_1"},
        {type="machine-row",id="machine_2",select="select_machine_2"},
        {type="machine-row",id="machine_3",select="select_machine_3"}
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
local function key(frame)
    return frame.network..":"..frame.machine..":"..frame.descriptor.id
end
app:onSnapshot(function(frame)
    local d=frame.descriptor
    if type(d.id)~="string" or #d.id>64
        or type(d.data)~="table" or type(d.controls)~="table" then return end
    local k=key(frame)
    peers[k]={key=k,network=frame.network,machine=frame.machine,
        id=d.id,title=d.title or d.id,seen=now(),
        data=d.data,graphs=d.graphs or {},controls=d.controls}
    local buckets=histories[k] or {}
    for _,graph in ipairs(d.graphs or {}) do
        if type(graph.id)=="string" then
            local samples=graph.samples or {}
            local latest=samples[#samples]
            if latest and type(latest.value)=="number" then
                local series=buckets[graph.id] or {}
                if #series==0 or series[#series].timestamp~=latest.timestamp then
                    series[#series+1]={timestamp=latest.timestamp or now(),value=latest.value}
                    if #series>120 then table.remove(series,1) end
                end
                buckets[graph.id]=series
            end
        end
    end
    histories[k]=buckets
    if not selectedKey then selectedKey=k end
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
        enabled=function() return ordered()[(machinePage-1)*3+i]~=nil end,
        run=function()
            local peer=ordered()[(machinePage-1)*3+i]
            if not peer then return false,"no machine" end
            selectedKey=peer.key
            app.monitorPendingControl=nil
            return app:showView("machine_data")
        end})
end
for _,entry in ipairs({
    {id="previous_machine_page",step=-1},
    {id="next_machine_page",step=1},
}) do
    local step=entry.step
    app:control(entry.id,{label=entry.id,remote=false,monitor=true,navigation=true,
        enabled=function() return #ordered()>3 end,
        run=function()
            local pages=math.max(1,math.ceil(#ordered()/3))
            machinePage=math.max(1,math.min(pages,machinePage+step))
            return true
        end})
end
for _,entry in ipairs({{"next_source","NEXT SOURCE",1},
                       {"previous_source","PREV SOURCE",-1}}) do
    local id,label,step=entry[1],entry[2],entry[3]
    app:control(id,{label=label,remote=false,monitor=true,navigation=true,run=function()
        local list=ordered()
        if #list==0 then return false,"no sources" end
        local current=1
        for i,peer in ipairs(list) do if peer.key==selectedKey then current=i end end
        selectedKey=list[(current-1+step+#list)%#list+1].key
        controlPage=1
        metricPage=1
        graphPage=1
        app.monitorPendingControl=nil
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
            and control.remote==true and control.enabled~=false then
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
local function remoteCards()
    local groups,order={},{}
    for _,item in ipairs(exposedControls()) do
        if item.uiHidden~=true then
            local category=type(item.category)=="string" and item.category~=""
                and item.category~="general" and item.category or "UNCATEGORIZED"
            if not groups[category] then
                groups[category]={};order[#order+1]=category
            end
            groups[category][#groups[category]+1]=item
        end
    end
    local cards={}
    for _,category in ipairs(order) do
        for first=1,#groups[category],6 do
            local part={}
            for j=first,math.min(first+5,#groups[category]) do
                part[#part+1]=groups[category][j]
            end
            cards[#cards+1]=part
        end
    end
    return cards
end
for slot=1,12 do
    local index=slot
    app:control("remote_export_"..index,{label="Remote export "..index,
        remote=false,monitor=true,confirm=true,
        enabled=function() return remoteAllowed() and peers[selectedKey]~=nil end,
        run=function()
            local peer=peers[selectedKey]
            if not remoteAllowed() or not peer then return false,"remote controls locked" end
            local staleMs=tonumber(app:config("supervision.staleMs",12000)) or 12000
            if now()-peer.seen>staleMs then return false,"source stale" end
            local cards=remoteCards()
            local page=math.max(1,app.displayPage or 1)
            local card=(page-1)*2+math.floor((index-1)/6)+1
            local control=cards[card] and cards[card][(index-1)%6+1]
            if not control then return false,"control unavailable" end
            local state=tostring(control.state or ""):lower()
            local command=state=="true" and control.trueControl
                or state=="false" and control.falseControl or nil
            command=command or control.id
            local exported=false
            for _,target in ipairs(peer.controls or {}) do
                if target.id==command and target.remote==true
                    and target.enabled~=false then
                    exported=true;break
                end
            end
            if not exported then return false,"target command not exported" end
            commandStatus="PENDING "..command
            local ok,err=app:remoteCommand(peer.machine,peer.id,command,{},function(success,reason)
                commandStatus=success and ("ACK "..command)
                    or ("ERROR "..tostring(reason))
            end)
            if not ok then commandStatus="REJECTED "..tostring(err) end
            return ok,err
        end})
end
app:maintenance("console",{title="Master supervision",
    status={
        {id="online",label="Online",read=function() return app.dataItems.online.value or 0 end},
        {id="total",label="Known",read=function() return app.dataItems.total.value or 0 end},
        {id="selected",label="Selected",read=function() return app.dataItems.selected.value or "--" end},
        {id="status",label="Status",read=function() return app.dataItems.status.value or "--" end}
    },tools={"previous_source","next_source"},logLimit=5})

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
    if not peer and list[1] then peer=list[1];selectedKey=peer.key end
    app:setRemoteExports("data",peer and peer.data or {})
    local remoteGraphs={}
    for _,graph in ipairs(peer and peer.graphs or {}) do
        local copy={}
        for k,v in pairs(graph) do copy[k]=v end
        copy.samples=(histories[peer.key] or {})[graph.id] or {}
        remoteGraphs[#remoteGraphs+1]=copy
    end
    app:setRemoteExports("graphs",remoteGraphs)
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
        web_status=(services.status("webbridge") or {}).status or "unknown",
        recent_event=events[1] and events[1] or "NO EVENTS",
        event_count=#events,event_1=events[1] or "--",
        event_2=events[2] or "--",event_3=events[3] or "--",
        nodes=#nodes,nodes_online=nodesOnline,conflicts=conflicts,
        total=#list,online=online,stale=#list-online,
        selected=peer and peer.machine or "NONE",
        machine=peer and peer.machine or "--",
        network=peer and peer.network or "--",
        age=age and math.floor(age/1000) or 0,
        metrics=peer and #peer.data or 0,
        controls=peer and #peer.controls or 0,
        status=not peer and "NO SOURCES" or
            (age<=staleAfter and "ONLINE" or "STALE")}
    machinePage=math.min(machinePage,math.max(1,math.ceil(#list/3)))
    for i=1,3 do
        local machine=list[(machinePage-1)*3+i]
        values["machine_"..i]=machine and (machine.machine.." / "..
            (now()-machine.seen<=staleAfter and "ONLINE" or "STALE")) or "--"
    end
    for id,value in pairs(values) do app:set(id,value) end
    for i=1,2 do
        local name="master_graph_"..i
        local graph=peer and peer.graphs and peer.graphs[(graphPage-1)*2+i]
        local source=graph and (peer.key..":"..tostring(graph.id)) or ""
        if app["source_"..name]~=source then
            app["source_"..name]=source
            app.graphs[name].samples={}
            app.graphs[name].label="--"
            app.graphs[name].unit=nil
        end
        local history=graph and histories[peer.key] and histories[peer.key][graph.id]
        if history then
            app.graphs[name].samples=history
            app.graphs[name].label=graph.label or graph.id
            app.graphs[name].unit=graph.unit
            app.graphs[name].min=graph.min;app.graphs[name].max=graph.max
            app.graphs[name].resolution=graph.resolution
            app.graphs[name].timeWindow=graph.timeWindow
        end
    end
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
    start=update,update=update})
return app
