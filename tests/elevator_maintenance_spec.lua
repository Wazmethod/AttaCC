-- Standalone CraftOS mock for compact maintenance controls.
local epoch=os.epoch
local time=100000
os.epoch=function() return time end
local function suite()
    local controls,status
    local actions={}
    local state={position="TOP",phase="IDLE",destination="-",
        top=true,bottom=false,callTop=false,callBottom=false,callCabin=false,
        error="-",polls=3,lastPollAgeMs=30}
    local app={
        control=function(_,key,action)
            controls=controls or {}
            controls[key]=action
        end,
        maintenance=function(_,key,definition)
            assert(key=="elevator")
            status=definition.status
        end,
        config=function(_,key,default)
            if key=="debug" then return true end
            if key=="motion.readOnly" then return true end
            return default
        end,
        invoke=function(_,action)
            actions[#actions+1]=action
            return true
        end,
    }
    local controller={snapshot=function() return state end}
    local refreshes=0
    dofile("apps/elevator/maintenance.lua").setup(app,controller,function()
        refreshes=refreshes+1
    end)
    assert(#status==8,"7 normal fields plus 1 debug field")
    assert(status[1].read()=="READ-ONLY")
    assert(status[2].read()=="TOP")
    assert(status[6].read()=="TOP=OFF BOTTOM=OFF CABIN=OFF")
    assert(status[8].read()=="3 polls; last 30 ms ago")
    assert(controls.maint_go_bottom.run())
    assert(#actions==0,"manual motion needs two clicks")
    assert(controls.maint_go_bottom.run())
    assert(actions[1]=="go_bottom" and refreshes==1)
    assert(controls.maint_stop.run())
    assert(actions[2]=="stop")
    assert(controls.maint_go_top.run())
    time=time+5001
    assert(controls.maint_go_top.run())
    assert(#actions==2,"expired confirmation must not move")
end
local ok,err=pcall(suite)
os.epoch=epoch
if not ok then error(err,0) end
print("Elevator compact maintenance checks: OK")
