-- Native SteamPlant telemetry. No internal AttaCC imports.
local M={}
local function bar(line,label)
    local value=(line or ""):match("^%s*"..label.."%s+(.+)$")
    if not value then return 0 end
    local filled,empty=0,0
    for i=1,#value do
        local byte=value:byte(i)
        if byte==127 then empty=empty+1 elseif byte~=32 then filled=filled+1 end
    end
    local total=filled+empty
    return total>0 and filled/total*100 or 0
end
function M.setup(app)
    local function call(role,method,fallback,...)
        local value,err=app:call(role,method,...)
        if err or value==nil then return fallback end
        return value
    end
    local function status(controller,rpm,capacity)
        local minRPM=tonumber(app:config("detection.onlineRpm",0)) or 0
        local minCap=tonumber(app:config("detection.onlineCapacity",0)) or 0
        if math.abs(rpm)>=minRPM and capacity>=minCap then return "RUNNING" end
        local state=controller.getState()
        if state=="AUTO_WAIT_RPM" or state=="AUTO_TRANSFER"
            or state=="AUTO_VERIFY" then return "STARTING" end
        if state=="AUTO_RETRY_WAIT" or controller.isPlantOffline() then return "OFFLINE" end
        if math.abs(rpm)<=app:config("detection.offlineRpm",0)
            and capacity<=app:config("detection.offlineCapacity",0) then return "STOPPED" end
        return "DEGRADED"
    end
    local function collect(controller,outputs)
        local l1=call("target","getLine","",1)
        local l2=call("target","getLine","",2)
        local l3=call("target","getLine","",3)
        local l4=call("target","getLine","",4)
        local raw=call("speedometer","getSpeed",0)
        local multiplier=tonumber(app:config("sensors.rpm.multiplier",1)) or 1
        local rpm=raw*multiplier
        local stress=call("stressometer","getStress",0)
        local capacity=call("stressometer","getStressCapacity",0)
        local energy=call("accumulator","getEnergy",0)
        local energyCapacity=call("accumulator","getCapacity",0)
        local sample={
            plant={status=status(controller,rpm,capacity)},
            power={rpm=rpm,rawRpm=raw,rpmMultiplier=multiplier,stress=stress,
                capacity=capacity,load=capacity>0 and stress/capacity*100 or 0,
                overstressed=call("stressometer","isOverstressed",false)},
            boiler={level=tonumber(l1:match("Lvl%s+(%d+)")) or 0,
                size=bar(l2,"Size"),water=bar(l3,"Water"),heat=bar(l4,"Heat")},
            battery={energy=energy,capacity=energyCapacity,
                percent=energyCapacity>0 and energy/energyCapacity*100 or 0,
                maxInsert=call("accumulator","getMaxInsert",0),
                maxExtract=call("accumulator","getMaxExtract",0)},
            motor={rpm=call("motor","getSpeed",0),
                direction=tonumber(app:config("motor.direction",1)) or 1,
                consumption=call("motor","getEnergyConsumption",0),
                stressCapacity=call("motor","getStressCapacity",0)},
            control={state=controller.getState(),error=controller.getError(),
                automatic=controller.isAutomatic(),armed=controller.isArmed(),
                plantOffline=controller.isPlantOffline(),
                mainClutchEngaged=outputs.mainEngaged(),
                alternatorClutchEngaged=outputs.alternatorEngaged(),
                genClutchEngaged=outputs.genEngaged()}
        }
        for id,value in pairs({rpm=sample.power.rpm,load=sample.power.load,
            water=sample.boiler.water,heat=sample.boiler.heat,
            battery=sample.battery.percent,motor_rpm=sample.motor.rpm}) do
            app:set(id,value)
            if type(value)=="number" then app:sample(id,value) end
        end
        return sample
    end
    return {collect=collect}
end
return M
