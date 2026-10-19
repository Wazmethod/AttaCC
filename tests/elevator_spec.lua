-- Standalone CraftOS controller test, no real redstone or Create blocks touched.
-- Run from the AttaCC root with: tests/elevator_spec.lua
local epoch=os.epoch
local timestamp=1000000
os.epoch=function() return timestamp end
local function test()
    local controller=require("apps.elevator.controller")
    local inputs={call_top=false,call_bottom=false,call_cabin=false,
        at_top=false,at_bottom=true}
    local outputs={clutch=false,gearshift=false}
    local writes={}
    local events={}
    local save={}
    local config={["motion.reverseForUp"]=false,["motion.settleMs"]=250,
        ["motion.timeoutSeconds"]=120}
    local app={
        networkTransport=nil,
        read=function(_,role) return inputs[role] end,
        write=function(_,role,value)
            outputs[role]=value
            writes[#writes+1]={role=role,value=value}
            return true
        end,
        state=function(_,key,value)
            if value==nil then return save[key] end
            save[key]=value
            return true
        end,
        config=function(_,path,fallback)
            local value=config[path]
            return value==nil and fallback or value
        end,
        emit=function(_,topic,event)
            events[#events+1]={topic=topic,code=event.code}
        end,
        log=function() end
    }
    local c=controller.new(app)
    assert(c.boot())
    assert(outputs.clutch==true,"clutch must stop at startup")
    assert(c.snapshot().position=="BOTTOM","bottom contact detection")
    assert(c.request("TOP","test"))
    assert(outputs.clutch==true,"hold clutch while changing direction")
    assert(outputs.gearshift==false,"unpowered gearshift climbs")
    timestamp=timestamp+150
    assert(c.update())
    assert(outputs.clutch==true,"hold until settleMs")
    timestamp=timestamp+150
    assert(c.update())
    assert(outputs.clutch==false,"release after settleMs")
    assert(c.snapshot().phase=="MOVING")
    inputs.at_bottom=false
    inputs.at_top=true
    timestamp=timestamp+150
    assert(c.update())
    assert(outputs.clutch==true,"clutch stops at destination")
    assert(c.snapshot().position=="TOP","arrived top")
    assert(c.snapshot().trips==1,"count completed trips")
    -- A brief arrival contact is enough; retained floor enables cabin call.
    inputs.at_top=false
    timestamp=timestamp+150
    c.update()
    assert(c.snapshot().position=="TOP","keep last floor after pulse")
    inputs.call_cabin=true
    timestamp=timestamp+150
    assert(c.update())
    assert(c.snapshot().destination=="BOTTOM","cabin button toggles floors")
    assert(outputs.gearshift==true,"powered gearshift descends")
    timestamp=timestamp+300
    assert(c.update())
    assert(outputs.clutch==false,"cabin request begins the return trip")
    assert(c.shutdown(),"shutdown must stop moving gantry")
    assert(outputs.clutch==true,"shutdown powers the clutch before SDK exits")
    assert(c.stop())
    assert(outputs.clutch==true,"stop cuts drive")
    inputs.call_cabin=false
    inputs.at_top=true
    inputs.at_bottom=true
    timestamp=timestamp+150
    assert(c.update()==false)
    local count=0
    for _,event in ipairs(events) do
        if event.code=="ELEVATOR_ERROR" then count=count+1 end
    end
    assert(count==1)
    timestamp=timestamp+150
    c.update()
    local later=0
    for _,event in ipairs(events) do
        if event.code=="ELEVATOR_ERROR" then later=later+1 end
    end
    assert(later==1,"identical errors should not flood logs")
end
local ok,err=pcall(test)
os.epoch=epoch
if not ok then error(err,0) end
print("Elevator SDK controller mock checks: OK")
