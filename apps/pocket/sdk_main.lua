-- AttaCC Pocket: SDK-native Minecraft network client.
local app=require("lib.attacc").app("pocket",{title="AttaCC Pocket"})
app:config({display={viewMode="views",mode="auto"},supervision={staleMs=12000,allowRemoteCommands=true}})
for _,dep in ipairs({"core.runtime","module.network","module.display"}) do app:require(dep) end
local sources,history,events={},{},{}
local graphHistory=require("lib.sdk_graph_history")
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
    app.displayPage=1
    app.monitorPendingControl=nil
    source()
end
-- The selected machine can publish several SDK applications.
-- Browse the actual application keys rather than reselecting the first app.
for _,spec in ipairs({{"previous_application",-1},{"next_application",1}}) do
    local id,step=spec[1],spec[2]
    app:control(id,{label=id,remote=false,monitor=true,navigation=true,
        enabled=function() return #entries(selectedMachine)>1 end,
        run=function()
            local list=entries(selectedMachine)
            if #list<2 then return false,"no other application" end
            local current=1
            for i,entry in ipairs(list) do
                if entry.key==selectedApp then current=i;break end
            end
            selectedApp=list[(current-1+step+#list)%#list+1].key
            metricPage,graphPage,controlPage=1,1,1
            app.displayPage=1
            app.monitorPendingControl=nil
            return true
        end})
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
        if type(control)=="table" and control.remote==true
            and control.enabled~=false and control.uiHidden~=true
            and type(control.id)=="string" then
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
    {"uptime","Uptime"},
    {"metric_1","Metric 1"},{"metric_2","Metric 2"},{"metric_3","Metric 3"},
    {"metric_category","Data category"},
    {"control","Control"},{"command","Command status"},
    {"machine_1","Machine 1"},{"machine_2","Machine 2"},{"machine_3","Machine 3"},
    {"event_1","Event 1"},{"event_2","Event 2"},{"event_3","Event 3"},
    {"event_filter","Event filter"},{"event_count","Event count"}
}
for _,item in ipairs(declarations) do app:data(item[1],{label=item[2]}) end
app:view("home",{label="HOME",columns=2,cardHeight=85,widgets={
    {type="group",label="NETWORK",items={"network","sources","online","machines","apps","master"}},
    {type="group",label="STORAGE",items={"storage"}}
}})
app:view("machines",{label="MACHINE",columns=1,cardHeight=35,
    dynamicRows=true,sourceNavigation={previous="previous_application",
        next="next_application",data="app"},
    navigation={previous="previous_machine_page",next="next_machine_page"},widgets={
        {type="machine-row",id="machine_1",select="select_machine_1",reboot="reboot_machine_1"},
        {type="machine-row",id="machine_2",select="select_machine_2",reboot="reboot_machine_2"},
        {type="machine-row",id="machine_3",select="select_machine_3",reboot="reboot_machine_3"}
}})
app:view("data",{parent="machines",label="DATA",columns=2,cardHeight=85,
    exportGroups="data",widgets={
        {type="group",label="APPLICATION",items={"app","source_status"}}
}})
app:view("graphs",{parent="machines",label="GRAPHS",columns=2,
    exportGroups="graphs",widgets={}})
app:view("controls",{parent="machines",label="CONTROLS",columns=2,
    cardHeight=85,exportGroups="controls",widgets={}})
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
    local previous=sources[id]
    local warnings=d.exportWarnings
    local truncated=type(warnings)=="table"
        and type(warnings.truncated)=="table" and next(warnings.truncated)~=nil
    if truncated and not (previous and previous.truncated) then
        app:toast("SOURCE EXPORTS TRUNCATED: "..d.id,"warning")
    end
    sources[id]={truncated=truncated,key=id,machine=frame.machine,appId=d.id,title=d.title or d.id,
        network=frame.network,data=d.data,graphs=d.graphs or {},controls=d.controls or {},seen=now()}
    history[id]=graphHistory.ingest(history[id],d.graphs,now())
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
    local policy=require("lib.sdk_auth").load()
    local client=policy and policy.client
    local me=app.networkTransport and app.networkTransport.machine.key
    return app:config("supervision.allowRemoteCommands",false)==true
        and app.remoteClient~=nil and type(client)=="table"
        and client.enabled==true and client.origin==me
        and type(client.secret)=="string" and #client.secret>=32
end
-- Graphics buttons use stable exported IDs. The renderer decides how many
-- controls fit on each page; Pocket has no numbered control proxy layer.
app.remoteDisplayUnavailableReason=function()
    local peer=source()
    if not peer then return "NO SOURCE SELECTED" end
    local staleMs=tonumber(app:config("supervision.staleMs",12000)) or 12000
    if now()-peer.seen>staleMs then return "SOURCE STALE" end
    if not remoteAllowed() then return "REMOTE CONTROL LOCKED" end
    return "REMOTE CONTROL UNAVAILABLE"
end
app.remoteDisplayReady=function()
    local peer=source()
    local staleMs=tonumber(app:config("supervision.staleMs",12000)) or 12000
    return remoteAllowed() and peer~=nil and now()-peer.seen<=staleMs
end
app.remoteDisplayIdentity=function()
    local peer=source()
    return peer and (tostring(peer.network)..":"..tostring(peer.machine)..":"..tostring(peer.appId)) or nil
end
app.remoteDisplayHandler=function(controlId,expectedSource)
    local peer=source()
    if not remoteAllowed() or not peer then return false,"remote controls locked" end
    local identity=tostring(peer.network)..":"..tostring(peer.machine)..":"..tostring(peer.appId)
    if identity~=expectedSource then return false,"remote source changed" end
    local staleMs=tonumber(app:config("supervision.staleMs",12000)) or 12000
    if now()-peer.seen>staleMs then return false,"source stale" end
    local command,err=require("lib.sdk_remote_controls").byId(peer.controls,controlId)
    if not command then return false,err end
    commandStatus="PENDING "..command
    app:toast(commandStatus,"info")
    local ok,reason=app:remoteCommand(peer.machine,peer.appId,command,{},function(success,detail)
        commandStatus=success and ("ACK "..command) or ("ERROR "..tostring(detail))
        app:toast(commandStatus,success and "success" or "error")
    end)
    if not ok then
        commandStatus="REJECTED "..tostring(reason)
        app:toast(commandStatus,"error")
    end
    return ok,reason
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
            app:toast("SENDING REBOOT "..machineName(key),"info")
            local ok,err=app:remoteCommand(key,remoteApp,"node_reboot",
                {confirm=true},function(success,reason)
                    commandStatus=success and ("REBOOT ACK "..machineName(key))
                        or ("ERROR "..tostring(reason))
                    app:toast(commandStatus,success and "success" or "error")
                end)
            if not ok then commandStatus="REJECTED "..tostring(err);app:toast(commandStatus,"error") end
            return ok,err
        end})
end
local function update()
    local machines=machineList()
    -- The Pocket's own CC is listed for discovery, but it is not a
    -- selectable remote source. Select the first actual SDK publisher.
    if not selectedMachine then
        local available=entries()
        if #available>0 then selectMachine(available[1].machine) end
    end
    local e=source()
    local selectedNode=selectedMachine and app:node(selectedMachine)
    app:set("uptime",selectedNode and selectedNode.uptimeSeconds and
        tostring(selectedNode.uptimeSeconds).." s" or "--")
    local dataExports={}
    for _,item in ipairs(e and e.data or {}) do dataExports[#dataExports+1]=item end
    if selectedNode and selectedNode.uptimeSeconds then
        dataExports[#dataExports+1]={id="node_uptime",label="Uptime",
            category="SYSTEM",value=selectedNode.uptimeSeconds,unit="s"}
    end
    app:setRemoteExports("data",dataExports)
    app:setRemoteExports("graphs",graphHistory.exports(e and e.graphs,e and history[e.key]))
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
