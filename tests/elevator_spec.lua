-- Standalone CraftOS mock: no real Redstone Links or movement.
local oldEpoch,oldTimer,oldCancel=os.epoch,os.startTimer,os.cancelTimer
local time=100000
local sequence=0
local cancelled={}
os.epoch=function() return time end
os.startTimer=function(delay)
    assert(delay>=0.05)
    sequence=sequence+1
    return sequence
end
os.cancelTimer=function(id) cancelled[id]=true end

local function test()
    local outputs={clutch=false,gearshift=false}
    local values={call_top=false,call_bottom=false,call_cabin=false,
        at_top=true,at_bottom=false}
    local config={
        ["motion.pollInterval"]=0.5,["motion.settleMs"]=250,
        ["motion.reverseForUp"]=false,["motion.timeoutSeconds"]=120,
        ["motion.readOnly"]=false
    }
    local stored={}
    local app={
        read=function(_,role) return values[role] end,
        write=function(_,role,value) outputs[role]=value;return true end,
        config=function(_,key,default)
            if config[key]==nil then return default end
            return config[key]
        end,
        state=function(_,key,value)
            if value==nil then return stored[key],"missing" end
            stored[key]=value
            return true
        end,
        log=function() end,
        emit=function() end,
    }
    local controller=require("apps.elevator.controller")
    local lift=controller.new(app)
    assert(lift.boot())
    assert(lift.snapshot().position=="TOP" and outputs.clutch)
    assert(lift.snapshot().phase=="IDLE")

    -- BOTTOM begins preparing on the ON edge; no falling edge needed.
    values.call_bottom=true
    time=time+500
    assert(lift.update())
    assert(lift.snapshot().phase=="PREPARING" and outputs.clutch)
    assert(lift.snapshot().callBottom)
    assert(outputs.gearshift==true,"powered gearshift descends")
    local release=sequence
    time=time+250
    assert(lift.onTimer(release)==true)
    assert(lift.snapshot().phase=="MOVING" and not outputs.clutch)
    assert(values.call_bottom,"button remained pressed during departure")

    -- Arrival stops the transmission and saves one trip.
    values.at_top=false
    values.at_bottom=true
    time=time+500
    assert(lift.update())
    assert(lift.snapshot().phase=="IDLE")
    assert(lift.snapshot().position=="BOTTOM" and outputs.clutch)
    assert(lift.snapshot().trips==1 and stored.trips.count==1)

    -- CABIN is the third physical button; it goes to the opposite floor.
    values.call_bottom=false
    assert(lift.update())
    values.call_cabin=true
    time=time+500
    assert(lift.update())
    assert(lift.snapshot().destination=="TOP")
    assert(lift.snapshot().phase=="PREPARING")
    assert(outputs.gearshift==false,"unpowered gearshift goes up")
    local cancelledRelease=sequence
    assert(lift.stop())
    assert(cancelled[cancelledRelease]==true)
    assert(lift.onTimer(cancelledRelease)==false)
    assert(lift.snapshot().phase=="IDLE" and outputs.clutch)

    -- Timer cannot release the clutch after controller updates have stopped.
    values.call_cabin=false
    lift.update()
    assert(lift.request("TOP","mock"))
    release=sequence
    time=time+3000
    assert(lift.onTimer(release)==false)
    assert(lift.snapshot().phase=="ERROR" and outputs.clutch)
    assert(lift.stop())

    -- Movement requests are blocked if polling is already stale.
    time=time+3000
    local ok,reason=lift.request("TOP","mock")
    assert(ok==false and tostring(reason):find("stale",1,true))
    assert(outputs.clutch)
    assert(lift.shutdown())

    -- Read-only mode keeps all three buttons observable without moving.
    config["motion.readOnly"]=true
    values.at_bottom=false
    values.at_top=true
    values.call_bottom=false
    values.call_cabin=false
    local safe=controller.new(app)
    assert(safe.boot())
    values.call_bottom=true
    time=time+500
    assert(safe.update())
    assert(safe.snapshot().callBottom and safe.snapshot().phase=="IDLE")
    assert(outputs.clutch)
    assert(safe.request("BOTTOM")==false)
    assert(safe.shutdown())
end
local ok,err=pcall(test)
os.epoch,os.startTimer,os.cancelTimer=oldEpoch,oldTimer,oldCancel
if not ok then error(err,0) end
print("Elevator simple controller checks: OK")
