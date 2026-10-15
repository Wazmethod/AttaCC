-- AttaCC SDK v1.1 adapter for SteamPlant.
-- Uses existing safety controller until the legacy application host is replaced.
local sdk = require("lib.attacc")
local controller = require("lib.controller")
local requirements = require("lib.attacc_requirements_steamplant")

local M = {}
local instance
function M.get()
    if instance then return instance end
    local app = sdk.app("steamplant", {title="SteamPlant Generator"})
    for id, spec in pairs(requirements) do
        app:io(id, {
            type=spec.type, direction=spec.direction,
            required=spec.required, label=spec.description or id,
            invert=spec.invert, readOutput=spec.readOutput,
        })
    end
    local latest = {}
    for _, item in ipairs({
        {"rpm","RPM","rpm"}, {"load","Mechanical load","%"},
        {"water","Boiler water","%"}, {"heat","Boiler heat","%"},
        {"battery","Accumulator","%"}, {"motor_rpm","Motor speed","rpm"},
    }) do
        local id, label, unit = item[1], item[2], item[3]
        app:data(id,{label=label,unit=unit,read=function() return latest[id] end})
        app:graph(id,{label=label,unit=unit,limit=120})
    end
    for _, command in ipairs({
        "procedure","abort","arm","disarm","main_on","main_off",
        "alt_on","alt_off","gen_on","gen_off",
        "motor_32","motor_64","motor_128","motor_stop",
        "running_topology","all_cut",
    }) do
        local id = command
        local requires = {}
        if id == "procedure" then
            requires={"motor","speedometer","stressometer","accumulator","target"}
        elseif id:match("^motor_%d+$") then
            requires={"motor"}
        end
        app:control(id,{
            label=id:gsub("_"," "):upper(), remote=true,
            confirm=id=="abort" or id=="all_cut",
            requires=requires,
            run=function() 
                local ok, err=controller.executeCommand(id)
                if not ok then error(err or "command rejected") end
                return true
            end
        })
    end
    app:view("overview",{
        label="SteamPlant",layout="dashboard",
        data={"rpm","load","water","heat","battery","motor_rpm"},
        controls={"procedure","abort","arm","disarm",
            "main_on","main_off","alt_on","alt_off","gen_on","gen_off",
            "motor_32","motor_64","motor_128","motor_stop",
            "running_topology","all_cut"}
    })
    app:maintenance("diagnostics",{
        title="SteamPlant Diagnostics",
        status={{id="controller",label="Controller state",read=controller.getState}},
        tools={"abort","motor_stop"},
    })
    instance=app
    M.latest=latest
    return app
end
function M.update(data)
    if not instance or type(data)~="table" then return end
    local values={
        rpm=data.power and data.power.rpm,
        load=data.power and data.power.load,
        water=data.boiler and data.boiler.water,
        heat=data.boiler and data.boiler.heat,
        battery=data.battery and data.battery.percent,
        motor_rpm=data.motor and data.motor.rpm,
    }
    for id, value in pairs(values) do
        M.latest[id]=value
        if type(value)=="number" then instance:sample(id,value) end
    end
end
return M
