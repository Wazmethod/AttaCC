local attacc=require("lib.attacc")
local app=attacc.app("node_agent",{title="AttaCC Node Agent"})
app:config({admin={enabled=false,actions={package_update=false,package_configure=false,reboot=false}}})
app:require("core.runtime")
app:require("module.network")
app:data("state",{label="Administration"})
app:view("home",{label="NODE",layout="widgets",widgets={{type="data",id="state"}}})
local function update()
    app:set("state",app:config("admin.enabled",false) and "ACL REQUIRED" or "DISABLED")
end
app:lifecycle({network=true,networkRequired=true,display=true,interval=2,
    nodeAdmin={enabled=app:config("admin.enabled",false),
        actions=app:config("admin.actions",{})},
    start=update,update=update})
return app
