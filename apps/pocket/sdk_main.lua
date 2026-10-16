-- SDK-native Pocket candidate. The original Pocket stays untouched until parity.
local attacc=require("lib.attacc")
local app=attacc.app("pocket_preview",{title="AttaCC Pocket SDK"})
app:config({supervision={staleMs=12000,allowRemoteCommands=false}})
app:require("core.runtime")
app:require("module.network")
app:require("module.display")
local sources={}
local selected=nil
local commandStatus="READ ONLY"
for _,field in ipairs({
    {"selected","Selected application"},{"machine","Machine"},
    {"online","Online sources"},{"sources","Known sources"},
    {"nodes","Discovered nodes"},{"network","Network"},
    {"status","Source status"},{"command","Command status"},
    {"data_1","Metric 1"},{"data_2","Metric 2"},
    {"data_3","Metric 3"},{"action","Selected remote control"}
}) do app:data(field[1],{label=field[2]}) end
app:view("home",{label="POCKET",layout="widgets",widgets={
    {type="data",id="sources"},{type="data",id="online"},
    {type="data",id="nodes"},{type="data",id="selected"},
    {type="data",id="status"},{type="data",id="network"}}})
app:view("data",{label="DATA",layout="widgets",widgets={
    {type="action",id="previous_source"},{type="data",id="machine"},
    {type="action",id="next_source"},
    {type="action",id="previous_metrics"},{type="action",id="next_metrics"},
    {type="data",id="data_1"},
    {type="data",id="data_2"},{type="data",id="data_3"}}})
app:view("controls",{label="CONTROLS",layout="widgets",widgets={
    {type="data",id="selected"},{type="data",id="action"},
    {type="data",id="command"},{type="action",id="previous_control"},
    {type="action",id="next_control"},{type="action",id="execute_control"}}})
local controlIndex=1
local metricPage=1
local function ordered()
    local list={}
    for _,entry in pairs(sources) do list[#list+1]=entry end
    table.sort(list,function(a,b) return a.key<b.key end)
    return list
end
local function active() return sources[selected] end
local function controls()
    local result={}
    local entry=active()
    for _,item in ipairs(entry and entry.controls or {}) do
        if type(item)=="table" and item.remote==true
            and item.enabled~=false and type(item.id)=="string" then
            result[#result+1]=item
        end
    end
    return result
end
app:onSnapshot(function(frame)
    local descriptor=frame.descriptor
    local id=frame.network..":"..frame.machine..":"..descriptor.id
    sources[id]={key=id,machine=frame.machine,network=frame.network,
        title=descriptor.title or descriptor.id,appId=descriptor.id,
        data=descriptor.data or {},controls=descriptor.controls or {},
        seen=os.epoch("utc")}
    if not selected then selected=id end
end)
for _,item in ipairs({{"previous_source",-1},{"next_source",1}}) do
    local id,delta=item[1],item[2]
    app:control(id,{label=id,remote=false,monitor=true,navigation=true,
        run=function()
            local list=ordered()
            if #list==0 then return false,"no sources" end
            local index=1
            for i,entry in ipairs(list) do
                if entry.key==selected then index=i;break end
            end
            selected=list[((index-1+delta+#list)%#list)+1].key
            controlIndex=1
            metricPage=1
            return true
        end})
end
for _,step in ipairs({{"previous_metrics",-1},{"next_metrics",1}}) do
    local id,delta=step[1],step[2]
    app:control(id,{label=id,remote=false,monitor=true,navigation=true,
        run=function()
            local entry=active()
            local pages=math.max(1,math.ceil(#(entry and entry.data or {})/3))
            metricPage=((metricPage-1+delta+pages)%pages)+1
            return true
        end})
end
for _,item in ipairs({{"previous_control",-1},{"next_control",1}}) do
    local id,delta=item[1],item[2]
    app:control(id,{label=id,remote=false,monitor=true,navigation=true,
        run=function()
            local count=#controls()
            if count==0 then return false,"no controls" end
            controlIndex=((controlIndex-1+delta+count)%count)+1
            return true
        end})
end
app:control("execute_control",{
    label="EXECUTE",remote=false,monitor=true,confirm=true,
    enabled=function()
        return app:config("supervision.allowRemoteCommands",false)==true
            and app.remoteClient~=nil and controls()[controlIndex]~=nil
    end,
    run=function()
        if app:config("supervision.allowRemoteCommands",false)~=true then
            return false,"remote commands disabled"
        end
        local entry=active()
        local target=controls()[controlIndex]
        if not entry or not target then return false,"no selected control" end
        local stale=tonumber(app:config("supervision.staleMs",12000)) or 12000
        if os.epoch("utc")-entry.seen>stale then return false,"source stale" end
        commandStatus="PENDING "..target.id
        local ok,result=app:remoteCommand(entry.machine,entry.appId,target.id,{},
            function(success,reason)
                commandStatus=success and ("ACK "..target.id)
                    or ("ERROR "..tostring(reason))
            end)
        if not ok then commandStatus="REJECTED "..tostring(result) end
        return ok,result
    end
})
local function update()
    local list=ordered()
    if not active() and list[1] then selected=list[1].key end
    local entry=active()
    local stale=tonumber(app:config("supervision.staleMs",12000)) or 12000
    local online=0
    for _,item in ipairs(list) do
        if os.epoch("utc")-item.seen<=stale then online=online+1 end
    end
    local data=entry and entry.data or {}
    metricPage=math.min(metricPage,math.max(1,math.ceil(#data/3)))
    local ctl=controls()[controlIndex]
    local values={sources=#list,online=online,nodes=#app:nodes(),
        selected=entry and entry.title or "NONE",
        machine=entry and entry.machine or "--",
        network=entry and entry.network or "--",
        status=entry and (os.epoch("utc")-entry.seen<=stale and "ONLINE" or "STALE") or "NO SOURCES",
        command=commandStatus,action=ctl and (ctl.label or ctl.id) or "--"}
    for i=1,3 do
        local item=data[(metricPage-1)*3+i]
        values["data_"..i]=item and
            (tostring(item.label or item.id)..": "..tostring(item.value==nil and "--" or item.value)) or "--"
    end
    for key,value in pairs(values) do app:set(key,value) end
end
app:lifecycle({interval=1,network=true,networkRequired=true,
    discoverNodes=true,remoteClient=true,display=true,
    start=update,update=update})
return app
