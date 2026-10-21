-- Standalone CraftOS mock for the simple 2-floor elevator.
-- Run from AttaCC root: tests/elevator_spec.lua
local previousEpoch=os.epoch
local timestamp=100000
os.epoch=function() return timestamp end

local function suite()
    local values={
        call_top=false,call_bottom=false,call_cabin=false,
        at_top=true,at_bottom=false
    }
    local outputs={clutch=false,gearshift=false}
    local writes={}
    local persisted={}
    local options={
        ["motion.pollInterval"]=0.5,["motion.readOnly"]=false,
        ["motion.reverseForUp"]=false,["motion.timeoutSeconds"]=120
    }
    local app={
        read=function(_,role) return values[role] end,
        write=function(_,role,value)
            outputs[role]=value
            writes[#writes+1]={role=role,value=value}
            return true
        end,
        config=function(_,key,fallback)
            if options[key]==nil then return fallback end
            return options[key]
        end,
        state=function(_,key,value)
            if value==nil then return persisted[key],"missing" end
            persisted[key]=value
            return true
        end,
        log=function() end,
        emit=function() end
    }
    local c=require("apps.elevator.controller").new(app)
    assert(c.boot())
    assert(c.snapshot().phase=="IDLE" and c.snapshot().position=="TOP")
    assert(outputs.clutch==true,"startup must stop transmission")

    -- BOTTOM rising edge starts motion in that very input scan.
    values.call_bottom=true
    timestamp=timestamp+500
    local count=#writes
    assert(c.update())
    assert(c.snapshot().phase=="MOVING","movement must begin on button ON")
    assert(c.snapshot().destination=="BOTTOM")
    assert(values.call_bottom==true,"button is still held")
    assert(outputs.clutch==false and outputs.gearshift==true)
    assert(#writes==count+3,"Clutch STOP, Gearshift, Clutch RELEASE")
    assert(writes[count+1].role=="clutch" and writes[count+1].value==true)
    assert(writes[count+2].role=="gearshift" and writes[count+2].value==true)
    assert(writes[count+3].role=="clutch" and writes[count+3].value==false)

    -- Button release must not be the trigger and must not change motion.
    values.call_bottom=false
    timestamp=timestamp+500
    assert(c.update())
    assert(c.snapshot().phase=="MOVING" and outputs.clutch==false)

    -- Destination contact stops the Gantry.
    values.at_top=false
    values.at_bottom=true
    timestamp=timestamp+500
    assert(c.update())
    assert(c.snapshot().phase=="IDLE")
    assert(c.snapshot().position=="BOTTOM" and outputs.clutch==true)
    assert(c.snapshot().trips==1 and persisted.trips.count==1)

    -- The third physical button (on the carriage) goes to opposite floor.
    values.call_cabin=true
    timestamp=timestamp+500
    assert(c.update())
    assert(c.snapshot().phase=="MOVING")
    assert(c.snapshot().destination=="TOP")
    assert(outputs.gearshift==false and outputs.clutch==false)
    assert(c.stop() and outputs.clutch==true)
    assert(c.snapshot().position=="BOTTOM")

    -- A STOP between floors must not guess the cabin's floor.
    values.call_cabin=false
    values.at_bottom=false
    timestamp=timestamp+500
    assert(c.update())
    assert(c.stop())
    assert(c.snapshot().position=="UNKNOWN")
    assert(c.cabin()==false)

    -- No movement if the controller hasn't polled sensors recently.
    timestamp=timestamp+3000
    local ok,reason=c.request("TOP","test")
    assert(ok==false and tostring(reason):find("stale",1,true))
    assert(outputs.clutch==true)

    -- Read-only still reads all inputs, without motor release.
    options["motion.readOnly"]=true
    values.at_top=true
    values.at_bottom=false
    values.call_bottom=false
    local safe=require("apps.elevator.controller").new(app)
    assert(safe.boot())
    values.call_bottom=true
    timestamp=timestamp+500
    assert(safe.update())
    assert(safe.snapshot().callBottom==true)
    assert(safe.snapshot().phase=="IDLE" and outputs.clutch==true)
    assert(safe.request("BOTTOM")==false)
    assert(safe.shutdown())
end

local ok,err=pcall(suite)
os.epoch=previousEpoch
if not ok then error(err,0) end
print("Elevator immediate ON-edge controller checks: OK")
