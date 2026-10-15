-- SteamPlant SDK-native composition root. The AttaCC runtime owns CraftOS.
local attacc=require("lib.attacc")
local app=attacc.app("steamplant",{title="SteamPlant Generator"})
app:requirements()
app:require("core.runtime")
app:config(require("config"))

local outputs=require("outputs").setup(app)
local controller=require("controller").setup(app,outputs)
local telemetry=require("telemetry").setup(app)

local metrics={
    {"rpm","RPM","rpm"},{"load","Mechanical load","%"},
    {"water","Boiler water","%"},{"heat","Boiler heat","%"},
    {"battery","Accumulator","%"},{"motor_rpm","Motor speed","rpm"}
}
for _,metric in ipairs(metrics) do
    app:data(metric[1],{label=metric[2],unit=metric[3]})
    app:graph(metric[1],{label=metric[2],unit=metric[3],limit=120})
end

local stateItems={
    {"plant_status","Plant status"},{"controller_state","Controller state"},
    {"controller_error","Controller error"},{"armed","Automatic restart armed"},
    {"automatic","Startup procedure active"},{"plant_offline","Plant offline"},
    {"main_clutch","Main clutch"},{"alternator_clutch","Alternator clutch"},
    {"gen_clutch","Generator clutch"}
}
for _,item in ipairs(stateItems) do
    app:data(item[1],{label=item[2]})
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
    elseif id:match("^motor_%d+$") or id=="motor_speed" then
        required={"motor"}
    end
    app:control(id,{
        label=id:gsub("_"," "):upper(),remote=true,
        confirm=id=="abort" or id=="all_cut",requires=required,
        run=function(args)
            local ok,err=controller.executeCommand(id,args)
            if not ok then return false,err end
            return true
        end
    })
end

-- Graphics monitor views are small, navigable screens instead of a long
-- auto-generated list of every hardware command.
for _,entry in ipairs({
    {id="show_overview",label="OVERVIEW",view="overview"},
    {id="show_graphs",label="GRAPHS",view="graphs"},
    {id="show_status",label="STATUS",view="status"},
}) do
    local page=entry.view
    app:control(entry.id,{label=entry.label,remote=false,run=function()
        return app:showView(page)
    end})
end
-- Declarative groups: the SDK displays these as category/subcategory tabs.
app:view("overview",{
    label="Plant overview",category="plant",categoryLabel="PLANT",subcategory="Overview",
    data={"rpm","load","water","heat","battery","motor_rpm"},
    controls={"show_graphs","show_status"}
})
app:view("status",{
    label="Plant status",category="plant",categoryLabel="PLANT",subcategory="Status",
    data={"plant_status","controller_state","controller_error",
        "armed","automatic","plant_offline"},
    controls={"show_overview","show_graphs"}
})
app:view("clutches",{
    label="Clutches",category="plant",categoryLabel="PLANT",subcategory="Clutches",
    data={"main_clutch","alternator_clutch","gen_clutch"}
})
app:view("graphs",{
    label="Telemetry history",category="telemetry",categoryLabel="TELEMETRY",subcategory="All",
    graphs={"rpm","load","water","heat","battery","motor_rpm"},
    controls={"show_overview","show_status"}
})
app:view("rotation",{
    label="Rotation",category="telemetry",categoryLabel="TELEMETRY",subcategory="Rotation",
    graphs={"rpm","motor_rpm","load"}
})
app:view("resources",{
    label="Resources",category="telemetry",categoryLabel="TELEMETRY",subcategory="Resources",
    graphs={"water","heat","battery"}
})

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
