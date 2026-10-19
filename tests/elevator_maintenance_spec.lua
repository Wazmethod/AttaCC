-- Isolated local maintenance test. No Create commands or world I/O.
-- From AttaCC checkout: tests/elevator_maintenance_spec.lua
local originalEpoch=os.epoch
local timestamp=1000000
os.epoch=function() return timestamp end
local function suite()
    local controls={}
    local definition
    local invoked={}
    local state={
        position="TOP",phase="IDLE",destination="-",
        top=true,bottom=false,callTop=false,callBottom=false,
        callCabin=false,error="-",updates=3,lastUpdateAgeMs=40,
        preparingElapsedMs=125,preparingRemainingMs=125,preparingDelayMs=250
    }
    local app={
        control=function(_,id,action)
            assert(not controls[id],"duplicate control: "..id)
            controls[id]=action
        end,
        maintenance=function(_,id,d)
            assert(id=="elevator")
            definition=d
        end,
        invoke=function(_,id)
            invoked[#invoked+1]=id
            if id=="go_bottom" then
                state.phase="PREPARING"
                state.destination="BOTTOM"
            elseif id=="stop" then
                state.phase="IDLE"
                state.destination="-"
            end
            return true
        end,
        log=function() end,
        config=function(_,key,fallback)
            if key=="motion.readOnly" then return true end
            if key=="motion.pollInterval" then return 1 end
            return fallback
        end
    }
    local controller={snapshot=function() return state end}
    local refreshCount=0
    local maintenance=dofile("apps/elevator/maintenance.lua")
    maintenance.setup(app,controller,function()
        refreshCount=refreshCount+1
    end,function() return "2 ticks; last 40 ms ago" end)
    assert(#definition.tools==3 and #definition.status==11)
    assert(definition.status[1].read()=="READ-ONLY / poll 1 s")
    assert(definition.status[2].read()=="TOP")
    assert(definition.status[8].read():find("3 %(last 40 ms ago%)"))
    assert(definition.status[9].read()=="2 ticks; last 40 ms ago")
    assert(definition.status[10].read()=="-")
    assert(controls.maint_go_bottom.run())
    assert(#invoked==0,"first click must never move gantry")
    assert(definition.status[7].read():find("CONFIRM"),"confirmation must be displayed")
    assert(controls.maint_go_bottom.run())
    assert(#invoked==1 and invoked[1]=="go_bottom")
    assert(state.phase=="PREPARING" and refreshCount==1)
    assert(controls.maint_go_top.run())
    timestamp=timestamp+5001
    assert(definition.status[7].read()=="READY","expired confirmation must reset")
    assert(controls.maint_go_top.run())
    assert(#invoked==1,"after timeout first click must re-arm only")
    assert(controls.maint_stop.run())
    assert(#invoked==2 and invoked[2]=="stop")
    assert(definition.status[7].read()=="READY","STOP must cancel confirmation")
    assert(controls.maint_go_top.run())
    assert(controls.maint_go_bottom.run())
    assert(controls.maint_go_top.run())
    assert(#invoked==2,"switching arming direction must never move")
end
local ok,err=pcall(suite)
os.epoch=originalEpoch
if not ok then error(err,0) end
print("Elevator maintenance mock checks: OK")
