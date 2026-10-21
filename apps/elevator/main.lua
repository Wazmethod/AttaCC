-- Independent AttaCC SDK example: two-floor Create gantry elevator.
local sdk=require("lib.attacc")
local app=sdk.app("elevator",{title="AttaCC Elevator"})
app:requirements()
app:require("core.runtime")
app:require("module.network")
app:require("module.display")
app:config(require("config"))
local controller=require("controller").new(app)
local diagnostics=require("diagnostics").new(app,controller)

for _,item in ipairs({
    {"position","Current floor","POSITION"},
    {"destination","Destination","POSITION"},
    {"phase","Motion state","MOTION"},
    {"clutch","Clutch stopped","MOTION","STOPPED","RUNNING"},
    {"at_top","Top sensor","SENSORS","ON","OFF"},
    {"at_bottom","Bottom sensor","SENSORS","ON","OFF"},
    {"call_top","Top button","CALL BUTTONS","PRESSED","RELEASED"},
    {"call_bottom","Bottom button","CALL BUTTONS","PRESSED","RELEASED"},
    {"call_cabin","Cabin button","CALL BUTTONS","PRESSED","RELEASED"},
    {"trips","Completed trips","STATISTICS"},
    {"error","Last error","STATUS"}
}) do
    app:data(item[1],{label=item[2],category=item[3],
        trueLabel=item[4],falseLabel=item[5]})
end

for _,action in ipairs({
    {id="go_top",label="GO TOP",floor="TOP",category="FLOORS"},
    {id="go_bottom",label="GO BOTTOM",floor="BOTTOM",category="FLOORS"},
    {id="cabin",label="CABIN TOGGLE",category="FLOORS"},
    {id="stop",label="STOP",category="MOTION"}
}) do
    local id,floor=action.id,action.floor
    app:control(id,{
        label=action.label,category=action.category,remote=true,
        confirm=id=="stop",monitor=true,
        run=function()
            if id=="stop" then return controller.stop() end
            if id=="cabin" then return controller.cabin() end
            return controller.request(floor,"SDK")
        end
    })
end
app:view("home",{label="ELEVATOR",layout="widgets",widgets={
    {type="group",label="POSITION",items={"position","destination","phase"}},
    {type="group",label="CALL",items={"at_top","at_bottom","trips"}},
    {type="action",id="go_top",label="TOP"},
    {type="action",id="go_bottom",label="BOTTOM"},
    {type="action",id="stop",label="STOP"}
}})
app:view("control",{label="CONTROLS",layout="widgets",widgets={
    {type="data",id="phase"},{type="data",id="position"},
    {type="action",id="go_top",label="GO TOP"},
    {type="action",id="go_bottom",label="GO BOTTOM"},
    {type="action",id="stop",label="STOP"}
}})
app:view("sensors",{label="SENSORS",layout="widgets",widgets={
    {type="data",id="at_top"},{type="data",id="at_bottom"},
    {type="data",id="call_top"},{type="data",id="call_bottom"},
    {type="data",id="call_cabin"},{type="data",id="clutch"},
    {type="data",id="error"}
}})
app.textSummary={title="ELEVATOR STATUS",sections={
    {label="POSITION",fields={{id="position",label="At"},
        {id="destination",label="Target"},{id="phase",label="State"}}},
    {label="IO",fields={{id="at_top",label="Top sensor",boolean=true},
        {id="at_bottom",label="Bottom sensor",boolean=true},
        {id="clutch",label="Stopped",boolean=true}}},
    {label="STATS",fields={{id="trips",label="Trips"},
        {id="error",label="Error"}}}
}}
local function refresh()
    local state=controller.snapshot()
    for id,value in pairs({
        position=state.position,destination=state.destination,
        phase=state.phase,clutch=state.clutchStopped,
        at_top=state.top,at_bottom=state.bottom,
        call_top=state.callTop,call_bottom=state.callBottom,
        call_cabin=state.callCabin,trips=state.trips,error=state.error
    }) do app:set(id,value) end
end
-- Keep the built-in CC terminal on the SDK's text maintenance screen.
-- The dedicated monitor views above remain completely unchanged.
require("maintenance").setup(app,controller,refresh,function() return diagnostics:snapshot() end)
app:lifecycle({
    -- App-local diagnostic knob: compare 150 ms polling against 1 second
    -- without modifying the shared SDK timer loop. Never use a slower
    -- polling rate for actual gantry travel without validating stopping.
    interval=app:config("motion.pollInterval",0.15),
    network=true,networkRequired=true,
    display=true,monitorMode=app:config("display.mode","auto"),
    monitorTextScale=app:config("display.textScale",0.5),
    start=function()
        local ok,err=controller.boot()
        if not ok then return false,err end
        refresh()
        diagnostics:start()
        return true
    end,
    update=function()
        controller.update()
        refresh()
    end,
    -- A redstone change on the CC or an attached CC:Tweaked relay raises
    -- a redstone event. React immediately; 150 ms polling is a fallback
    -- if an event is missed or a peripheral does not propagate changes.
    handlers={
        timer=function(_,timerId)
            -- Elevator's one-shot preparation timer must run independently
            -- of the slower Bridge input polling. Unknown timer IDs are
            -- left to the existing diagnostic probe.
            local before=controller.snapshot()
            controller.onTimer(timerId)
            local after=controller.snapshot()
            if after.phase~=before.phase or after.error~=before.error then refresh() end
            diagnostics:onTimer(timerId)
        end,
        redstone=function()
            controller.update()
            refresh()
        end,
        -- CC: Create Redstone Link can emit this when a watched frequency
        -- changes. Basic bridge variants continue using periodic polling.
        redstone_link_change=function(_,freq1,freq2,newStrength,oldStrength,color1,color2)
            -- In event-input mode, the bridge provides the new sensor value.
            -- Do not call getLinkSignal again (which can swallow timers
            -- while yielding to the Minecraft server thread).
            if controller.onLinkChange(freq1,freq2,newStrength,color1,color2) then
                controller.update()
                refresh()
            elseif app:config("diagnostics.bridgeEvents",false)~=true then
                controller.update()
                refresh()
            end
        end
    },
    -- SDK host calls this on normal termination or an event-loop failure.
    shutdown=function() return controller.shutdown() end
})
return app
