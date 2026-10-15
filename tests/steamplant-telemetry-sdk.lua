-- Hardware-free contract for SteamPlant native telemetry module.
local values,samples={},{}
local app={
    call=function(_,role,method,...)
        if role=="target" then return "Water "..string.char(1,1,1,127),nil end
        local results={speedometer={getSpeed=128},
            stressometer={getStress=40,getStressCapacity=100,isOverstressed=false},
            accumulator={getEnergy=50,getCapacity=100},
            motor={getSpeed=128}}
        return results[role] and results[role][method] or nil,nil
    end,
    config=function(_,name,fallback)
        local cfg={["detection.onlineRpm"]=100,["detection.onlineCapacity"]=20,
            ["detection.offlineRpm"]=5,["detection.offlineCapacity"]=5}
        return cfg[name] or fallback
    end,
    set=function(_,id,value) values[id]=value end,
    sample=function(_,id,value) samples[id]=value end
}
local ctrl={
    getState=function() return "RUNNING" end,
    getError=function() return nil end,
    isAutomatic=function() return false end,
    isArmed=function() return true end,
    isPlantOffline=function() return false end
}
local outputs={
    mainEngaged=function() return true end,
    alternatorEngaged=function() return false end,
    genEngaged=function() return true end
}
local module=dofile("apps/steamplant/telemetry.lua").setup(app)
local result=module.collect(ctrl,outputs)
assert(result.plant.status=="RUNNING")
assert(values.rpm==128 and values.load==40)
assert(values.battery==50 and samples.rpm==128)
assert(result.control.mainClutchEngaged==true)
print("SteamPlant native telemetry contract: OK")
