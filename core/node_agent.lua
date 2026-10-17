-- Native AttaCC node agent, independent from any application preset.
-- Publishes discovery/snapshot and accepts signed system commands only.
local app=require("lib.attacc").app("runtime",{title="AttaCC Node Runtime"})
app:config({admin={enabled=false,actions={reboot=false}},
    display={mode="text"}})
app:require("core.runtime")
app:lifecycle({
    interval=2,network=true,networkRequired=true,display=false,
    discoverNodes=false,announceNode=true,
})
return app
