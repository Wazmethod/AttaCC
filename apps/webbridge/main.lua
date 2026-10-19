-- Standalone SDK WebBridge, deployable on a dedicated CC or beside any app.
-- The backend receives supervision only; web commands remain read-only.
local attacc=require("lib.attacc")
local app=attacc.app("webbridge",{title="AttaCC WebBridge SDK"})
app:require("core.runtime")
app:require("module.network")
app:config({bridge={interval=1}})
local relay=require("lib.sdk_webbridge_relay").new(app)
local machine=require("lib.machine").get(app.id)
local fields={
    {"connection","Web connection"},
    {"network","Logical network"},
    {"machine","Bridge machine"},
    {"snapshots","Snapshots forwarded"},
    {"events","Events forwarded"},
    {"status","Bridge status"}
}
for _,field in ipairs(fields) do
    app:data(field[1],{label=field[2],category="WEBBRIDGE"})
end
app:view("home",{label="WEBBRIDGE",layout="widgets",widgets={
    {type="data",id="connection"},{type="data",id="status"},
    {type="data",id="network"},{type="data",id="machine"},
    {type="data",id="snapshots"},{type="data",id="events"}
}})
local function update()
    relay:tick()
    local snapshots,events=relay:stats()
    app:set("connection",relay:status())
    app:set("network",machine.network)
    app:set("machine",machine.key)
    app:set("snapshots",snapshots)
    app:set("events",events)
    app:set("status",relay.enabled and "SDK READ ONLY" or "NOT CONFIGURED")
end
app:lifecycle({
    interval=app:config("bridge.interval",1),
    network=true,networkRequired=true,discoverNodes=true,
    display=false, -- headless; do not claim the attached monitor
    websocket=relay.websocket,
    start=update,update=update
})
return app
