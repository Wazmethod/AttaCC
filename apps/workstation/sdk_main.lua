-- SDK-native Workstation candidate. Legacy console/storage UI remains untouched.
local attacc=require("lib.attacc")
local app=attacc.app("workstation_preview",{title="AttaCC Workstation SDK"})
app:require("core.runtime")
app:require("module.network")
app:require("module.display")
app:config({supervision={staleMs=12000}})
local peers={}
for _,field in ipairs({
    {"hostname","Workstation"},{"sources","Applications"},
    {"online","Online applications"},{"nodes","Known nodes"},
    {"nodes_online","Online nodes"},{"conflicts","Node identity conflicts"},
    {"selected","Selected node"},{"role","Node role"},
    {"node_status","Node status"},{"runtime","Runtime entries"}
}) do app:data(field[1],{label=field[2]}) end
app:view("home",{label="HOME",layout="widgets",widgets={
    {type="data",id="hostname"},{type="data",id="sources"},
    {type="data",id="online"},{type="data",id="nodes"},
    {type="data",id="nodes_online"},{type="data",id="conflicts"}}})
app:view("nodes",{label="NODES",layout="widgets",widgets={
    {type="action",id="previous_node"},{type="data",id="selected"},
    {type="action",id="next_node"},{type="data",id="role"},
    {type="data",id="node_status"},{type="data",id="runtime"}}})
app:onSnapshot(function(frame)
    local id=frame.network..":"..frame.machine..":"..frame.descriptor.id
    peers[id]=os.epoch("utc")
end)
local index=1
for _,item in ipairs({{"previous_node",-1},{"next_node",1}}) do
    local id,delta=item[1],item[2]
    app:control(id,{label=id,remote=false,monitor=true,navigation=true,
        run=function()
            local nodes=app:nodes()
            if #nodes==0 then return false,"no discovered nodes" end
            index=((index-1+delta+#nodes)%#nodes)+1
            return true
        end})
end
local function update()
    local now=os.epoch("utc")
    local stale=tonumber(app:config("supervision.staleMs",12000)) or 12000
    local n,online=0,0
    for _,seen in pairs(peers) do
        n=n+1
        if now-seen<=stale then online=online+1 end
    end
    local nodes=app:nodes()
    index=math.max(1,math.min(index,#nodes))
    local node=nodes[index]
    local onlineNodes,conflicts=0,0
    for _,item in ipairs(nodes) do
        if item.online then onlineNodes=onlineNodes+1 end
        if item.conflict then conflicts=conflicts+1 end
    end
    local machine=require("lib.machine").get(app.id)
    local values={
        hostname=machine.hostname or machine.key,
        sources=n,online=online,nodes=#nodes,nodes_online=onlineNodes,
        conflicts=conflicts,selected=node and node.hostname or "NONE",
        role=node and node.role or "--",
        node_status=node and (node.online and "ONLINE" or "STALE") or "--",
        runtime=node and #(node.runtime or {}) or 0}
    for key,value in pairs(values) do app:set(key,value) end
end
app:lifecycle({interval=1,network=true,networkRequired=true,
    discoverNodes=true,display=true,start=update,update=update})
return app
