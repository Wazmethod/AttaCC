-- SDK-native storage host. Backends are reused without legacy network protocol.
local attacc=require("lib.attacc")
local app=attacc.app("storage_agent",{title="AttaCC Storage SDK"})
app:require("core.runtime")
app:require("module.network")
app:config({storageService={enabled=false,actions={
    ping=true,namespaces=true,list=true,get=true,set=false,delete=false
}}})
app:data("service",{label="Storage API"})
app:data("node",{label="Machine"})
app:view("home",{label="STORAGE",layout="widgets",widgets={
    {type="data",id="service"},{type="data",id="node"}
}})
local function update()
    local enabled=app:config("storageService.enabled",false)==true
    app:set("service",enabled and "SIGNED SDK" or "DISABLED")
    app:set("node",require("lib.machine").get(app.id).key)
end
app:lifecycle({network=true,networkRequired=true,display=true,interval=2,
    storageService={
        enabled=app:config("storageService.enabled",false),
        actions=app:config("storageService.actions",{}),
        backendConfig=app:config("storageBackend",{})
    },
    start=update,update=update})
return app
