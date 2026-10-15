-- Master V1.1 native SDK candidate. Not a replacement for legacy master yet.
-- Receives typed SDK snapshots; never issues hardware commands in this preview.
local attacc=require("lib.attacc")
local app=attacc.app("master",{title="AttaCC Master"})
app:config({display={viewMode="views",mode="auto",textScale=0.5},
    supervision={staleMs=12000}})
app:require("core.runtime")
app:require("module.network")
app:require("module.display")

local peers={}
local function now() return os.epoch("utc") end
for _,field in ipairs({
    {"online","Online applications"},{"total","Known applications"},
    {"stale","Stale applications"},{"selected","Selected application"},
    {"machine","Machine"},{"network","Network"},
    {"age","Snapshot age","s"},{"metrics","Exported metrics"},
    {"controls","Remote controls"},{"status","Application status"}
}) do app:data(field[1],{label=field[2],unit=field[3]}) end

app:view("overview",{label="HOME",layout="widgets",widgets={
    {type="data",id="online",label="ONLINE"},
    {type="data",id="total",label="KNOWN"},
    {type="data",id="stale",label="STALE"},
    {type="data",id="selected",label="APP"},
    {type="data",id="machine",label="MACHINE"},
    {type="data",id="status",label="STATUS"}
}})
app:view("details",{label="DETAILS",layout="widgets",widgets={
    {type="data",id="selected",label="APP"},
    {type="data",id="machine",label="HOST"},
    {type="data",id="network",label="NETWORK"},
    {type="data",id="age",label="AGE"},
    {type="data",id="metrics",label="METRICS"},
    {type="data",id="controls",label="CONTROLS"}
}})
app:view("sources",{label="SOURCES",layout="widgets",widgets={
    {type="data",id="total",label="KNOWN"},
    {type="data",id="online",label="ONLINE"},
    {type="data",id="stale",label="STALE"}
}})

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
    local values={
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
app:lifecycle({interval=1,network=true,networkRequired=true,display=true,
    monitorTextScale=app:config("display.textScale",0.5),
    monitorMode=app:config("display.mode","auto"),
    start=update,update=update})
return app
