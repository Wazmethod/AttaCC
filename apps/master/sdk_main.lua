-- Master V1.1 native SDK candidate. Not a replacement for legacy master yet.
-- Receives typed SDK snapshots; never issues hardware commands in this preview.
local attacc=require("lib.attacc")
local app=attacc.app("master_preview",{title="AttaCC Master SDK Preview"})
app:config({display={viewMode="views",mode="auto",textScale=0.5},
    supervision={staleMs=12000}})
app:require("core.runtime")
app:require("module.network")
app:require("module.display")

local peers={}
local events={}
local limit=100
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
    {"metric_2","Metric 2"},{"metric_3","Metric 3"}
}) do app:data(field[1],{label=field[2],unit=field[3]}) end

-- Preserve the historical HOME / MACHINE / EVENTS / NETWORK navigation.
-- The historical MACHINE page has DATA / GRAPHS / CONTROLS tabs.
local function cards(items)
    local out={}
    for _,id in ipairs(items) do out[#out+1]={type="data",id=id} end
    return out
end
app:view("home",{label="HOME",layout="widgets",widgets=cards({
    "online","nodes_online","recent_event","storage_status","web_status","status"
})})
app:view("machine",{label="MACHINE",layout="widgets",widgets=cards({
    "selected","machine","status","metric_1","metric_2","metric_3"
})})
app:view("machine_graphs",{label="GRAPHS",layout="widgets",widgets=cards({
    "selected","machine","metrics","age"
})})
app:view("machine_controls",{label="CONTROLS",layout="widgets",widgets=cards({
    "selected","machine","controls","status"
})})
app:view("events",{label="EVENTS",layout="widgets",widgets=cards({
    "recent_event"
})})
app:view("network",{label="NETWORK",layout="widgets",widgets=cards({
    "nodes","nodes_online","conflicts","total","stale","network"
})})

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
        data=d.data,controls=d.controls}
    if not selectedKey then selectedKey=k end
end)

local function ordered()
    local result={}
    for _,peer in pairs(peers) do result[#result+1]=peer end
    table.sort(result,function(a,b) return a.key<b.key end)
    return result
end
for _,entry in ipairs({{"next_source","NEXT SOURCE",1},
                       {"previous_source","PREV SOURCE",-1}}) do
    local id,label,step=entry[1],entry[2],entry[3]
    app:control(id,{label=label,remote=false,monitor=false,run=function()
        local list=ordered()
        if #list==0 then return false,"no sources" end
        local current=1
        for i,peer in ipairs(list) do if peer.key==selectedKey then current=i end end
        selectedKey=list[(current-1+step+#list)%#list+1].key
        return true
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
    local list=ordered()
    local online=0
    local staleAfter=tonumber(app:config("supervision.staleMs",12000)) or 12000
    for _,peer in ipairs(list) do
        if now()-peer.seen<=staleAfter then online=online+1 end
    end
    local peer=peers[selectedKey]
    if not peer and list[1] then peer=list[1];selectedKey=peer.key end
    local age=peer and math.max(0,now()-peer.seen) or nil
    local nodes=app.nodeDiscovery and app.nodeDiscovery:list() or {}
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
    local values={
        metric_1=metrics[1] or "--",metric_2=metrics[2] or "--",
        metric_3=metrics[3] or "--",
        storage_status="NOT MIGRATED",web_status="NOT MIGRATED",
        recent_event=events[1] and events[1] or "NO EVENTS",
        nodes=#nodes,nodes_online=nodesOnline,conflicts=conflicts,
        total=#list,online=online,stale=#list-online,
        selected=peer and peer.title or "NONE",
        machine=peer and peer.machine or "--",
        network=peer and peer.network or "--",
        age=age and math.floor(age/1000) or 0,
        metrics=peer and #peer.data or 0,
        controls=peer and #peer.controls or 0,
        status=not peer and "NO SOURCES" or
            (age<=staleAfter and "ONLINE" or "STALE")}
    for id,value in pairs(values) do app:set(id,value) end
end
local function receiveEvent(_,channel,msg)
    if type(msg)~="table" or msg.type~="module_event" then return end
    local expected=require("lib.machine").get(app.id).network
    if msg.network and msg.network~=expected then return end
    local entry=(tostring(msg.hostname or msg.machine or "?").." "..
        tostring(msg.code or "EVENT")..": "..tostring(msg.message or "")):sub(1,160)
    table.insert(events,1,entry)
    while #events>limit do table.remove(events) end
end
app:lifecycle({interval=1,network=true,networkRequired=true,discoverNodes=true,display=true,
    eventChannels={4247,4254},onNetworkEvent=receiveEvent,
    monitorTextScale=app:config("display.textScale",0.5),
    monitorMode=app:config("display.mode","auto"),
    start=update,update=update})
return app
