-- SteamPlant SDK-native composition root. The AttaCC runtime owns CraftOS.
local attacc=require("lib.attacc")
local app=attacc.app("steamplant",{title="SteamPlant Generator"})
app:requirements()
app:require("core.runtime")
app:config(require("config"))

local outputs=require("outputs").setup(app)
local controller=require("controller").setup(app,outputs)
local telemetry=require("telemetry").setup(app)

-- Categories and graph axes are owned by SteamPlant, not Pocket/Master.
-- resolution is the horizontal time grid in seconds; timeWindow is seconds.
local metrics={
    {"rpm","RPM","rpm","GENERATOR"},
    {"load","Mechanical load","%","GENERATOR",0,100},
    {"water","Boiler water","%","BOILER",0,100},
    {"heat","Boiler heat","%","BOILER",0,100},
    {"battery","Accumulator","%","ENERGY",0,100},
    {"motor_rpm","Motor speed","rpm","MOTOR"}
}
for _,metric in ipairs(metrics) do
    app:data(metric[1],{label=metric[2],unit=metric[3],category=metric[4]})
    app:graph(metric[1],{label=metric[2],unit=metric[3],category=metric[4],
        min=metric[5],max=metric[6],resolution=30,timeWindow=120,limit=120})
end

local stateItems={
    {"plant_status","Plant status","STATUS"},
    {"controller_state","Controller state","STATUS"},
    {"controller_error","Controller error","STATUS"},
    {"armed","Automatic restart armed","AUTOMATION","ARMED","DISARMED"},
    {"automatic","Startup procedure active","AUTOMATION","ACTIVE","INACTIVE"},
    {"plant_offline","Plant offline","STATUS","OFFLINE","ONLINE"},
    {"main_clutch","Main clutch","CLUTCHES","ENGAGED","DISENGAGED"},
    {"alternator_clutch","Alternator clutch","CLUTCHES","ENGAGED","DISENGAGED"},
    {"gen_clutch","Generator clutch","CLUTCHES","ENGAGED","DISENGAGED"}
}
for _,item in ipairs(stateItems) do
    app:data(item[1],{label=item[2],category=item[3],
        trueLabel=item[4],falseLabel=item[5]})
end

local commands={
    "procedure","abort","arm","disarm","main_on","main_off",
    "alt_on","alt_off","gen_on","gen_off",
    "motor_32","motor_64","motor_128","motor_stop","motor_speed",
    "running_topology","all_cut"
}
for _,name in ipairs(commands) do
    local id=name
    local required={}
    if id=="procedure" then
        required={"motor","speedometer","stressometer","accumulator","target"}
    elseif id=="running_topology" then
        required={"speedometer","stressometer","main_clutch","gen_clutch","alternator_clutch","motor"}
    elseif id:match("^motor_%d+$") or id=="motor_speed" then
        required={"motor"}
    end
    app:control(id,{
        label=id=="procedure" and "START" or id:gsub("_"," "):upper(),remote=true,
        uiHidden=(id=="arm" or id=="disarm" or id=="main_on" or id=="main_off"
            or id=="alt_on" or id=="alt_off" or id=="gen_on" or id=="gen_off"),
        category=(id=="procedure" or id=="abort") and "AUTOMATION"
            or (id=="arm" or id=="disarm") and "AUTOMATION"
            or (id:match("^main_") or id:match("^alt_") or id:match("^gen_"))
                and "CLUTCHES"
            or id:match("^motor_") and "MOTOR" or "SAFETY",
        confirm=id=="abort" or id=="all_cut",requires=required,
        monitor=id~="motor_speed" and id~="running_topology",
        state=function()
            if id=="arm" or id=="disarm" then
                return controller.isArmed() and "ARMED" or "DISARMED"
            end
            if id=="main_on" or id=="main_off" then
                return tostring(app.dataItems.main_clutch.value)
            end
            if id=="alt_on" or id=="alt_off" then
                return tostring(app.dataItems.alternator_clutch.value)
            end
            if id=="gen_on" or id=="gen_off" then
                return tostring(app.dataItems.gen_clutch.value)
            end
            return tostring(controller.getState())
        end,
        run=function(args)
            local ok,err=controller.executeCommand(id,args)
            if not ok then return false,err end
            return true
        end
    })
end

-- Source-owned toggle exports: Pocket and Master render one stateful
-- button while the underlying guarded physical commands stay individually
-- callable through authenticated SDK control requests.
for _,spec in ipairs({
    {id="restart_toggle",label="Auto restart",category="AUTOMATION",
        current=function() return controller.isArmed() end,
        on="arm",off="disarm",trueLabel="DISARM",falseLabel="ARM"},
    {id="main_toggle",label="Main clutch",category="CLUTCHES",
        current=function() return app.dataItems.main_clutch.value==true end,
        on="main_on",off="main_off",trueLabel="DISENGAGE MAIN",falseLabel="ENGAGE MAIN"},
    {id="alternator_toggle",label="Alternator clutch",category="CLUTCHES",
        current=function() return app.dataItems.alternator_clutch.value==true end,
        on="alt_on",off="alt_off",trueLabel="DISENGAGE ALT",falseLabel="ENGAGE ALT"},
    {id="generator_toggle",label="Generator clutch",category="CLUTCHES",
        current=function() return app.dataItems.gen_clutch.value==true end,
        on="gen_on",off="gen_off",trueLabel="DISENGAGE GEN",falseLabel="ENGAGE GEN"}
}) do
    local item=spec
    app:control(item.id,{
        label=item.label,category=item.category,remote=true,
        monitor=true,confirm=true,toggle=true,
        state=item.current,trueLabel=item.trueLabel,falseLabel=item.falseLabel,
        trueControl=item.off,falseControl=item.on,
        run=function()
            local action=item.current() and item.off or item.on
            return controller.executeCommand(action,{})
        end
    })
end

-- Graphics monitor views are small, navigable screens instead of a long
-- auto-generated list of every hardware command.
for _,entry in ipairs({
    {id="show_overview",label="OVERVIEW",view="overview"},
    {id="show_graphs",label="GRAPHS",view="graphs"},
    {id="show_status",label="STATUS",view="control"},
}) do
    local page=entry.view
    app:control(entry.id,{label=entry.label,remote=false,run=function()
        return app:showView(page)
    end})
end
-- Monitor views are explicit compositions of already-exported SDK data
-- and commands. A toggle pairs ON/OFF actions with an exported state.
app:view("overview",{
    label="HOME",layout="widgets",
    widgets={
        {type="data",id="rpm",label="RPM",precision=2},
        {type="data",id="load",label="LOAD",precision=2},
        {type="data",id="battery",label="BAT",precision=2},
        {type="data",id="water",label="WATER",precision=2},
        {type="data",id="heat",label="HEAT",precision=2},
        {type="data",id="motor_rpm",label="MOTOR",precision=2}
    }
})
app:view("graphs",{
    label="GRAPHS",layout="widgets",widgets={
        {type="graph",id="rpm",label="RPM"},
        {type="graph",id="load",label="LOAD"},
        {type="graph",id="water",label="WATER"},
        {type="graph",id="heat",label="HEAT"},
        {type="graph",id="battery",label="BAT"},
        {type="graph",id="motor_rpm",label="MOTOR"}
    }
})
app:view("control",{
    label="CONTROL",layout="widgets",widgets={
        {type="toggle",state="main_clutch",on="main_on",off="main_off",label="MAIN"},
        {type="toggle",state="gen_clutch",on="gen_on",off="gen_off",label="GEN"},
        {type="toggle",state="alternator_clutch",on="alt_on",off="alt_off",label="ALT"},
        {type="toggle",state="armed",on="arm",off="disarm",label="AUTO"},
        {type="action",id="procedure",label="START"},
        {type="action",id="abort",label="ABORT"},
        {type="action",id="motor_stop",label="MOTOR STOP"},
        {type="action",id="all_cut",label="ALL CUT"}
    }
})
-- Read-only monitor text status, independent from the selected graphics view.
-- Grouping and priorities are app-defined; the SDK owns responsive drawing.
app.textSummary={
    title="STEAMPLANT STATUS",
    sections={
        {label="PLANT",fields={
            {id="plant_status",label="Plant"},
            {id="controller_state",label="Controller"},
            {id="plant_offline",label="Offline",boolean=true}}},
        {label="POWER",fields={
            {id="rpm",label="RPM",precision=1},
            {id="load",label="Load",precision=2},
            {id="battery",label="Battery",precision=2},
            {id="water",label="Water",precision=1},
            {id="heat",label="Heat",precision=1},
            {id="motor_rpm",label="Motor",precision=1}}},
        {label="CONTROL",fields={
            {id="armed",label="Auto armed",boolean=true},
            {id="automatic",label="Starting",boolean=true},
            {id="main_clutch",label="Main clutch",boolean=true},
            {id="gen_clutch",label="Gen clutch",boolean=true},
            {id="alternator_clutch",label="Alt clutch",boolean=true}}},
        {label="FAULT",fields={{id="controller_error",label="Last error"}}}
    }
}

-- Native CraftOS console (Workstation-style). This is not the dashboard.
app:maintenance("console",{
    title="SteamPlant",
    status={
        {id="plant",label="Plant",read=function() return controller.getState() end},
        {id="armed",label="Auto restart",read=function()
            return controller.isArmed() and "ARMED" or "DISARMED"
        end},
        {id="rpm",label="Rotation",read=function()
            return tostring(app.dataItems.rpm.value or "--").." rpm"
        end},
        {id="load",label="Mechanical load",read=function()
            return string.format("%.1f%%",tonumber(app.dataItems.load.value) or 0)
        end},
        {id="water",label="Boiler water",read=function()
            return string.format("%.1f%%",tonumber(app.dataItems.water.value) or 0)
        end},
        {id="battery",label="Accumulator",read=function()
            return string.format("%.1f%%",tonumber(app.dataItems.battery.value) or 0)
        end},
    },
    tools={"abort","disarm","arm","procedure"},
    logLimit=4
})

controller.setEventSink(function(event)
    app:emit("steamplant.event",event)
    app:log(event.level or "info",tostring(event.code)..": "..tostring(event.message))
end)

local function sample()
    local frame=telemetry.collect(controller,outputs)
    local power=frame.power
    local c=frame.control
    local states={
        plant_status=frame.plant.status,
        controller_state=c.state,controller_error=c.error or "-",
        armed=c.armed,automatic=c.automatic,plant_offline=c.plantOffline,
        main_clutch=c.mainClutchEngaged,alternator_clutch=c.alternatorClutchEngaged,
        gen_clutch=c.genClutchEngaged
    }
    for id,value in pairs(states) do app:set(id,value) end
    if not controller.isInitialized() then controller.initialize(power) end
    controller.updateDetection(power)
    controller.update()
    return frame
end

app:lifecycle({
    interval=1,
    network=true,
    networkRequired=true,
    display=true,
    monitorName=app:config("display.monitorName"),
    monitorTextScale=app:config("display.textScale",0.5),
    monitorMode=app:config("display.mode","auto"),
    monitorTouchProfile=app:config("display.touchProfile","normal"),
    monitorTouchFlipX=app:config("display.touchFlipX",false),
    monitorTouchFlipY=app:config("display.touchFlipY",false),
    monitorTouchInsetX=app:config("display.touchInsetX",0),
    monitorTouchInsetY=app:config("display.touchInsetY",0),
    start=function()
        if app:config("commissioning.allowOutputs",false)~=true then
            return false,"outputs locked: set commissioning.allowOutputs=true only on a secured test rig"
        end
        local ok,err=controller.prepareBootOutputs()
        if not ok then return false,err end
        sample()
        return true
    end,
    update=function()
        sample()
    end
})

return app
