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
    local reads=0
    local events={}
    local save={}
    local config={["motion.reverseForUp"]=false,["motion.settleMs"]=250,
        ["motion.timeoutSeconds"]=120}
    local app={
        networkTransport=nil,
        read=function(_,role)
            reads=reads+1
            return inputs[role]
        end,
        write=function(_,role,value)
            outputs[role]=value
            writes[#writes+1]={role=role,value=value}
            return true
        end,
        state=function(_,key,value)
            if value==nil then
                if save[key]==nil then return nil,"missing" end
                return save[key]
            end
            if type(value)~="table" then
                return false,"persistent state must be a table"
            end
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
    assert(c.snapshot().preparingDelayMs==250)
    assert(c.snapshot().preparingRemainingMs==250)
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
    assert(type(save.trips)=="table" and save.trips.count==1,
        "trip count must be saved as SDK JSON table")
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
    -- Check both directions when powered Gearshift is configured to climb.
    config["motion.reverseForUp"]=true
    inputs.at_top=false
    inputs.at_bottom=true
    local c2=controller.new(app)
    assert(c2.snapshot().trips==1,"persisted trip count must survive restart")
    assert(c2.boot())
    assert(c2.request("TOP","polarity check"))
    assert(outputs.gearshift==true,"powered gearshift climbs when configured")
    assert(c2.stop())
    inputs.at_top=true
    inputs.at_bottom=false
    assert(c2.update())
    assert(c2.request("BOTTOM","polarity check"))
    assert(outputs.gearshift==false,"unpowered gearshift descends when configured")
    assert(c2.shutdown())

    -- A stalled scheduler must not trigger delayed motion unexpectedly.
    inputs.at_top=false
    inputs.at_bottom=true
    config["motion.settleMs"]=250
    local c3=controller.new(app)
    assert(c3.boot())
    assert(c3.request("TOP","stalled timer test"))
    timestamp=timestamp+6000
    assert(c3.update()==false,"preparing beyond 5 seconds must fail safe")
    assert(c3.snapshot().phase=="ERROR")
    assert(c3.snapshot().error:find("preparing stalled",1,true))
    assert(outputs.clutch==true,"stalled preparing must hold Clutch stopped")
    assert(c3.snapshot().updates==1)
    assert(c3.shutdown())

    -- Local commands must not arm PREPARING when the main SDK timer has
    -- already stopped being delivered.
    inputs.at_bottom=true
    inputs.at_top=false
    config["motion.pollInterval"]=0.15
    local stale=controller.new(app)
    assert(stale.boot())
    timestamp=timestamp+3001
    local accepted,reason=stale.request("TOP","stale")
    assert(accepted==false and tostring(reason):find("controller updates stale",1,true))
    assert(stale.snapshot().phase=="IDLE","stale timer must not arm motion")
    assert(outputs.clutch==true,"stale timer rejection must keep Clutch stopped")
    config["motion.readOnly"]=true
    accepted,reason=stale.request("TOP","read-only")
    assert(accepted==false and tostring(reason):find("read-only",1,true))
    assert(stale.snapshot().phase=="IDLE")
    assert(stale.shutdown())

    -- Isolate the suspect Bridge method calls without disabling the
    -- SDK timer, UI or network activity. This is read-only mode ONLY.
    config["diagnostics.skipInputPolling"]=true
    config["motion.readOnly"]=true
    local isolated=controller.new(app)
    assert(isolated.boot())
    local atBoot=reads
    timestamp=timestamp+150
    assert(isolated.update())
    timestamp=timestamp+150
    assert(isolated.update())
    assert(reads==atBoot,"read-only cached-input diagnostic must bypass periodic Bridge reads")
    assert(isolated.snapshot().updates==2)
    -- Even if the read-only flag is cleared at runtime, never skip live
    -- sensor reads and never allow this mode to hide real motion inputs.
    config["motion.readOnly"]=false
    timestamp=timestamp+150
    assert(isolated.update())
    assert(reads==atBoot+5,"live operation must always sample all inputs")
    assert(isolated.shutdown())

    -- Event-driven, watch-capable Bridge: no periodic reads after boot,
    -- events update inputs and the controller still advances on SDK ticks.
    local savedPeripheral=peripheral
    local savedRegistry=package.loaded["lib.io_registry"]
    peripheral={
        isPresent=function(name) return name=="bridge_0" end,
        getMethods=function()
            return {"getLinkSignal","sendLinkSignal","watchLinkSignal"}
        end
    }
    local freqs={
        call_top="minecraft:iron_ingot",
        call_bottom="minecraft:gold_ingot",
        call_cabin="minecraft:diamond",
        at_top="minecraft:oak_log",
        at_bottom="minecraft:blackstone"
    }
    package.loaded["lib.io_registry"]={
        describe=function(_,name)
            local role=name:match("^elevator%.(.+)$")
            if not role or not freqs[role] then return nil end
            return {
                driver="create.redstone_link",peripheral="bridge_0",
                freq1=freqs[role],freq2="minecraft:redstone",
                direction="input"
            }
        end
    }
    -- The real io_registry.describe is a module function; the mock above
    -- intentionally accepts its single name argument.
    package.loaded["lib.io_registry"].describe=function(name)
        local role=name:match("^elevator%.(.+)$")
        if not role or not freqs[role] then return nil end
        return {
            driver="create.redstone_link",peripheral="bridge_0",
            freq1=freqs[role],freq2="minecraft:redstone",
            direction="input"
        }
    end
    config["motion.readOnly"]=true
    config["diagnostics.skipInputPolling"]=false
    config["diagnostics.bridgeEvents"]=true
    inputs.at_top=true
    inputs.at_bottom=false
    local watched=controller.new(app)
    assert(watched.boot())
    local atStart=reads
    timestamp=timestamp+150
    assert(watched.update())
    assert(reads==atStart,"event-mode timer must not poll Bridge")
    assert(watched.onLinkChange(freqs.at_bottom,"minecraft:redstone",15)==true)
    assert(watched.onLinkChange(freqs.at_top,"minecraft:redstone",0)==true)
    timestamp=timestamp+150
    assert(watched.update())
    assert(watched.snapshot().position=="BOTTOM","change events refresh floor state")
    assert(reads==atStart,"link events must not call getLinkSignal")
    assert(watched.request("TOP","test")==false,"watch commissioning is read-only")
    assert(watched.shutdown())
    peripheral.getMethods=function() return {"getLinkSignal","sendLinkSignal"} end
    local unwatched=controller.new(app)
    local ready,why=unwatched.boot()
    assert(ready==false and tostring(why):find("watchLinkSignal",1,true),
        "basic Bridge must be rejected by event mode")
    assert(unwatched.shutdown())
    package.loaded["lib.io_registry"]=savedRegistry
    peripheral=savedPeripheral
end
local ok,err=pcall(test)
os.epoch=epoch
if not ok then error(err,0) end
print("Elevator SDK controller mock checks: OK")
