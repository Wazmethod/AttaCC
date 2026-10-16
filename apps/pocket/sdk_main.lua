-- AttaCC Pocket: SDK-native Minecraft network client.
local app=require("lib.attacc").app("pocket",{title="AttaCC Pocket"})
app:config({display={viewMode="views",mode="auto"},supervision={staleMs=12000,allowRemoteCommands=false}})
for _,dep in ipairs({"core.runtime","module.network","module.display"}) do app:require(dep) end
local sources,history,events={},{},{}
local selectedMachine,selectedApp,eventMachine=nil,nil,nil
local metricPage,graphPage,controlPage,machinePage,eventPage=1,1,1,1,1
local commandStatus="READ ONLY"
local MAX_EVENTS=120
local function now() return os.epoch("utc") end
local function machineList()
    local names,seen={},{}
    local me=app.networkTransport and app.networkTransport.machine.key
    if me then names[#names+1]=me;seen[me]=true end
    for _,node in ipairs(app:nodes()) do
        if not seen[node.key] then names[#names+1]=node.key;seen[node.key]=true end
    end
    for _,entry in pairs(sources) do
        if not seen[entry.machine] then names[#names+1]=entry.machine;seen[entry.machine]=true end
    end
    table.sort(names,function(a,b)
        if a==me then return true end
        if b==me then return false end
        return a<b
    end)
    return names
end
local function entries(machine)
    local list={}
    for _,source in pairs(sources) do
        if not machine or source.machine==machine then list[#list+1]=source end
    end
    table.sort(list,function(a,b) return a.key<b.key end)
    return list
end
local function machineName(key)
    if not key then return "--" end
    local node=app:node(key)
    return node and node.hostname or key
end
local function source()
    local list=entries(selectedMachine)
    for _,entry in ipairs(list) do if entry.key==selectedApp then return entry end end
    selectedApp=list[1] and list[1].key or nil
    return list[1]
end
local function selectMachine(key)
    selectedMachine=key;selectedApp=nil
    metricPage,graphPage,controlPage=1,1,1
    source()
end
-- Exports are paged by category, never mixed across category boundaries.
local function categoryPages(items,size)
    local groups,order={},{}
    for _,item in ipairs(items or {}) do
        local category=type(item.category)=="string" and item.category~="" and item.category or "general"
        if not groups[category] then groups[category]={};order[#order+1]=category end
        groups[category][#groups[category]+1]=item
    end
    local result={}
    for _,category in ipairs(order) do
        local group=groups[category]
        for first=1,#group,size do
            local page={category=category,items={}}
            for j=first,math.min(first+size-1,#group) do
                page.items[#page.items+1]=group[j]
            end
            result[#result+1]=page
        end
    end
    if #result==0 then result[1]={category="general",items={}} end
    return result
end
local function availableControls()
    local result={}
    local entry=source()
    for _,control in ipairs(entry and entry.controls or {}) do
        if control.remote==true and control.enabled~=false and type(control.id)=="string" then
            result[#result+1]=control
        end
    end
    return result
end
local declarations={
    {"network","Network"},{"sources","Known sources"},{"online","Online applications"},
    {"machines","Known machines"},{"apps","Applications"},{"master","Master"},
    {"storage","Storage"},{"selected","Selected machine"},{"app","Selected application"},
    {"status","Machine status"},{"source_status","Application status"},
    {"metric_1","Metric 1"},{"metric_2","Metric 2"},{"metric_3","Metric 3"},
    {"metric_category","Data category"},
    {"control","Control"},{"command","Command status"},
    {"machine_1","Machine 1"},{"machine_2","Machine 2"},{"machine_3","Machine 3"},
    {"event_1","Event 1"},{"event_2","Event 2"},{"event_3","Event 3"},
    {"event_filter","Event filter"},{"event_count","Event count"}
}
for _,item in ipairs(declarations) do app:data(item[1],{label=item[2]}) end
app:graph("pocket_graph_1",{label="Graph 1",limit=120})
app:graph("pocket_graph_2",{label="Graph 2",limit=120})
app:view("home",{label="HOME",columns=2,cardHeight=85,widgets={
    {type="group",label="NETWORK",items={"network","sources","online","machines","apps","master"}},
    {type="group",label="STORAGE",items={"storage"}}
}})
app:view("data",{label="MACHINE",columns=2,cardHeight=85,exportGroups="data",
    sourceNavigation={titleOnly=true,data="selected"},
    widgets={
        {type="group",label="APPLICATION",items={"app","source_status"}}
}})
app:view("graphs",{parent="data",label="GRAPHS",columns=2,exportGroups="graphs",
    widgets={
        {type="graph",id="pocket_graph_1"},{type="graph",id="pocket_graph_2"}
}})
app:view("controls",{parent="data",label="CONTROLS",columns=2,cardHeight=85,
    exportGroups="controls",widgets={}})
app:view("machines",{parent="data",label="MACHINES",columns=1,cardHeight=35,
    dynamicRows=true,
    navigation={previous="previous_machine_page",next="next_machine_page"},widgets={
        {type="machine-row",id="machine_1",select="select_machine_1",reboot="reboot_machine_1"},
        {type="machine-row",id="machine_2",select="select_machine_2",reboot="reboot_machine_2"},
        {type="machine-row",id="machine_3",select="select_machine_3",reboot="reboot_machine_3"}
}})
app:view("events",{label="EVENTS",columns=2,cardHeight=85,
    navigation={previous="previous_event_page",next="next_event_page"},widgets={
        {type="action",id="previous_event_machine",label="< FILTER"},
        {type="action",id="next_event_machine",label="FILTER >"},
        {type="group",label="NETWORK EVENTS",items={"event_filter","event_count","event_1","event_2","event_3"}}
}})
app:onSnapshot(function(frame)
    local d=frame.descriptor
    if type(d)~="table" or type(d.id)~="string" or type(d.data)~="table" then return end
    local id=frame.network..":"..frame.machine..":"..d.id
    sources[id]={key=id,machine=frame.machine,appId=d.id,title=d.title or d.id,
        data=d.data,graphs=d.graphs or {},controls=d.controls or {},seen=now()}
    local bucket=history[id] or {}
    for _,g in ipairs(d.graphs or {}) do
        if type(g.id)=="string" then
            local series=bucket[g.id] or {}
            local latest=(g.samples or {})[#(g.samples or {})]
            if latest and type(latest.value)=="number" then
                local last=series[#series]
                if not last or last.timestamp~=latest.timestamp then
                    series[#series+1]={timestamp=latest.timestamp or now(),value=latest.value}
                    while #series>120 do table.remove(series,1) end
                end
            end
            bucket[g.id]=series
        end
    end
    history[id]=bucket
    if not selectedMachine then selectMachine(frame.machine) end
end)
-- One SDK wildcard subscription captures arbitrary event codes from the network.
app:onNetwork("*",function(payload,frame)
    if frame.topic=="node.status" then return end
    local code=tostring(payload.code or payload.id or frame.topic)
    local info=tostring(payload.info or payload.message or payload.detail or "")
    events[#events+1]={machine=frame.origin,code=code,info=info,at=frame.timestamp or now()}
    if #events>MAX_EVENTS then table.remove(events,1) end
end)
local function stepMachine(delta)
    local list=machineList()
    if #list==0 then return false,"no machines" end
    local pos=1
    for i,key in ipairs(list) do if key==selectedMachine then pos=i;break end end
    selectMachine(list[((pos-1+delta+#list)%#list)+1])
    return true
end
local function nav(id,fn)
    app:control(id,{label=id,remote=false,monitor=true,navigation=true,run=fn})
end
nav("previous_machine",function() return stepMachine(-1) end)
nav("next_machine",function() return stepMachine(1) end)
local function stepPage(field,delta,size,max)
    return math.max(1,math.min(max,field+delta))
end
local function changePage(kind,delta)
    local e=source()
    local items=kind=="metrics" and (e and e.data or {})
        or kind=="graphs" and (e and e.graphs or {})
        or availableControls()
    local size=kind=="graphs" and 2 or kind=="metrics" and 3 or 1
    local max=#categoryPages(items,size)
    if kind=="metrics" then metricPage=stepPage(metricPage,delta,size,max)
    elseif kind=="graphs" then graphPage=stepPage(graphPage,delta,size,max)
    else controlPage=stepPage(controlPage,delta,size,max) end
    return true
end
for _,kind in ipairs({"metrics","graphs","controls"}) do
    nav("previous_"..kind,function() return changePage(kind,-1) end)
    nav("next_"..kind,function() return changePage(kind,1) end)
end
local function eventMachines()
    local list={"ALL"}
    for _,key in ipairs(machineList()) do list[#list+1]=key end
    return list
end
local function moveEventFilter(delta)
    local list=eventMachines()
    local pos=1
    for i,key in ipairs(list) do if key==(eventMachine or "ALL") then pos=i;break end end
    local choice=list[((pos-1+delta+#list)%#list)+1]
    eventMachine=choice=="ALL" and nil or choice
    eventPage=1
    return true
end
nav("previous_event_machine",function() return moveEventFilter(-1) end)
nav("next_event_machine",function() return moveEventFilter(1) end)
nav("previous_event_page",function() eventPage=math.max(1,eventPage-1);return true end)
nav("next_event_page",function() eventPage=eventPage+1;return true end)
nav("previous_machine_page",function() machinePage=math.max(1,machinePage-1);return true end)
nav("next_machine_page",function() machinePage=machinePage+1;return true end)
for i=1,3 do
    local slot=i
    app:control("select_machine_"..i,{label="SELECT "..i,remote=false,monitor=true,navigation=true,
        enabled=function()
            local key=machineList()[(machinePage-1)*3+slot]
            return key~=nil and key~=(app.networkTransport and app.networkTransport.machine.key)
        end,
        run=function()
            local key=machineList()[(machinePage-1)*3+slot]
            if not key then return false,"no machine in slot" end
            selectMachine(key)
            return app:showView("data")
        end})
end
local function remoteAllowed()
    return app:config("supervision.allowRemoteCommands",false)==true
        and app.remoteClient~=nil
end
-- The display exposes buttons directly from the remote control descriptor.
-- Slots follow the same six-per-group layout, two cards per page on Pocket.
local function sortedRemoteGroups()
    local groups,order={},{}
    for _,item in ipairs(source() and source().controls or {}) do
        if item.remote==true and item.enabled~=false then
            local category=type(item.category)=="string" and item.category~=""
                and item.category~="general" and item.category or "UNCATEGORIZED"
            if not groups[category] then groups[category]={};order[#order+1]=category end
            groups[category][#groups[category]+1]=item
        end
    end
    local cards={}
    for _,category in ipairs(order) do
        local items=groups[category]
        for first=1,#items,6 do
            local card={}
            for j=first,math.min(first+5,#items) do card[#card+1]=items[j] end
            cards[#cards+1]=card
        end
    end
    return cards
end
for i=1,12 do
    local slot=i
    app:control("remote_export_"..i,{label="Remote export "..i,remote=false,
        monitor=true,confirm=true,enabled=function()
            return remoteAllowed() and source()~=nil
        end,
        run=function()
            local e=source()
            if not remoteAllowed() or not e then return false,"remote control locked" end
            local stale=tonumber(app:config("supervision.staleMs",12000)) or 12000
            if now()-e.seen>stale then return false,"source stale" end
            local cards=sortedRemoteGroups()
            local page=math.max(1,app.displayPage or 1)
            local cardIndex=(page-1)*2+math.floor((slot-1)/6)+1
            local control=cards[cardIndex] and cards[cardIndex][(slot-1)%6+1]
            if not control then return false,"control unavailable" end
            local state=tostring(control.state or ""):lower()
            local command=state=="true" and control.trueControl
                or state=="false" and control.falseControl or nil
            command=command or control.id
            local allowed=false
            for _,item in ipairs(e.controls or {}) do
                if item.id==command and item.remote==true and item.enabled~=false then
                    allowed=true;break
                end
            end
            if not allowed then return false,"remote action not exported" end
            commandStatus="PENDING "..command
            local ok,err=app:remoteCommand(e.machine,e.appId,command,{},function(success,reason)
                commandStatus=success and ("ACK "..command)
                    or ("ERROR "..tostring(reason))
            end)
            if not ok then commandStatus="REJECTED "..tostring(err) end
            return ok,err
        end})
end
for i=1,3 do
    local slot=i
    local function target()
        return machineList()[(machinePage-1)*3+slot]
    end
    local function rebootReady()
        local key=target()
        if not key then return false end
        if key==(app.networkTransport and app.networkTransport.machine.key) then return true end
        if not remoteAllowed() then return false end
        local stale=tonumber(app:config("supervision.staleMs",12000)) or 12000
        for _,entry in ipairs(entries(key)) do
            if now()-entry.seen<=stale then
                for _,control in ipairs(entry.controls or {}) do
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
            local key=target()
            if not rebootReady() or not key then return false,"reboot locked" end
            if key==(app.networkTransport and app.networkTransport.machine.key) then
                os.queueEvent("attacc_pocket_self_reboot")
                return true
            end
            local remoteApp
            for _,entry in ipairs(entries(key)) do
                for _,control in ipairs(entry.controls or {}) do
                    if control.id=="node_reboot" and control.remote==true
                        and control.enabled~=false then remoteApp=entry.appId;break end
                end
                if remoteApp then break end
            end
            if not remoteApp then return false,"reboot unavailable" end
            commandStatus="PENDING REBOOT "..machineName(key)
            local ok,err=app:remoteCommand(key,remoteApp,"node_reboot",
                {confirm=true},function(success,reason)
                    commandStatus=success and ("REBOOT ACK "..machineName(key))
                        or ("ERROR "..tostring(reason))
                end)
            if not ok then commandStatus="REJECTED "..tostring(err) end
            return ok,err
        end})
end
local function update()
    local machines=machineList()
    if not selectedMachine and #machines>0 then selectMachine(machines[1]) end
    local e=source()
    app:setRemoteExports("data",e and e.data or {})
    app:setRemoteExports("graphs",e and e.graphs or {})
    app:setRemoteExports("controls",e and e.controls or {})
    local stale=tonumber(app:config("supervision.staleMs",12000)) or 12000
    local online=0
    for _,entry in pairs(sources) do if now()-entry.seen<=stale then online=online+1 end end
    local master="NONE"
    for _,node in ipairs(app:nodes()) do
        if node.role=="master" or node.preset=="master" or node.key=="master" then
            master=node.hostname or node.key;break
        end
    end
    local network=app.networkTransport and app.networkTransport.machine.network or "default"
    local controlPages=categoryPages(availableControls(),1)
    controlPage=math.min(controlPage,#controlPages)
    local ctl=controlPages[controlPage].items[1]
    local values={network=network,sources=#entries(),online=online,machines=#machines,
        apps=#entries(),master=master,storage="NOT CONFIGURED",
        selected=machineName(selectedMachine),app=e and e.title or "--",
        status=selectedMachine and "KNOWN" or "--",
        source_status=e and (now()-e.seen<=stale and "ONLINE" or "STALE") or "NO APP",
        command=commandStatus,control=ctl and
            ((ctl.category and ctl.category~="general" and (ctl.category.." / ") or "")
                ..tostring(ctl.label or ctl.id)) or "--"}
    local data=e and e.data or {}
    local dataPages=categoryPages(data,3)
    metricPage=math.min(metricPage,#dataPages)
    local activeData=dataPages[metricPage]
    values.metric_category=activeData.category
    for i=1,3 do
        local item=activeData.items[i]
        values["metric_"..i]=item and
            (tostring(item.label or item.id)..": "..tostring(item.value==nil and "--" or item.value)) or "--"
    end
    local graphs=e and e.graphs or {}
    local graphPages=categoryPages(graphs,2)
    graphPage=math.min(graphPage,#graphPages)
    local activeGraphs=graphPages[graphPage]
    for i=1,2 do
        local target=app.graphs["pocket_graph_"..i]
        local graph=activeGraphs.items[i]
        local identity=graph and (e.key..":"..tostring(graph.id)) or ""
        if target.remoteIdentity~=identity then
            target.remoteIdentity=identity;target.samples={}
            target.label="--";target.unit=nil
        end
        if graph then
            target.label=(activeGraphs.category~="general" and (activeGraphs.category.." / ") or "")
                ..tostring(graph.label or graph.id or "GRAPH")
            target.unit=graph.unit
            target.min=graph.min;target.max=graph.max
            target.resolution=graph.resolution;target.timeWindow=graph.timeWindow
            target.samples=(history[e.key] or {})[graph.id] or {}
        end
    end
    machinePage=math.min(machinePage,math.max(1,math.ceil(#machines/3)))
    for i=1,3 do
        local key=machines[(machinePage-1)*3+i]
        local node=key and app:node(key)
        values["machine_"..i]=key and
            (machineName(key).." / "..(node and node.online and "ONLINE" or "KNOWN")) or "--"
    end
    local filtered={}
    for i=#events,1,-1 do
        if not eventMachine or events[i].machine==eventMachine then filtered[#filtered+1]=events[i] end
    end
    eventPage=math.min(eventPage,math.max(1,math.ceil(#filtered/3)))
    values.event_filter=eventMachine and machineName(eventMachine) or "ALL MACHINES"
    values.event_count=#filtered
    for i=1,3 do
        local event=filtered[(eventPage-1)*3+i]
        values["event_"..i]=event and (machineName(event.machine).." / "..event.code.." / "..event.info) or "--"
    end
    for id,value in pairs(values) do app:set(id,value) end
end
app:lifecycle({interval=1,network=true,networkRequired=true,discoverNodes=true,
    remoteClient=true,display=true,terminalAppView=true,
    terminalMode=app:config("display.mode","auto"),start=update,update=update,
    handlers={attacc_pocket_self_reboot=function() os.reboot() end}})
return app
