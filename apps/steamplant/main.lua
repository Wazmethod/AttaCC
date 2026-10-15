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

app:view("overview",{
    label="SteamPlant",layout="dashboard",
    data={"rpm","load","water","heat","battery","motor_rpm"},
    graphs={"rpm","load","water","heat","battery","motor_rpm"},
    controls=commands
})

controller.setEventSink(function(event)
    app:emit("steamplant.event",event)
    app:log(event.level or "info",tostring(event.code)..": "..tostring(event.message))
end)

local function sample()
    local frame=telemetry.collect(controller,outputs)
    local power=frame.power
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
    start=function()
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
