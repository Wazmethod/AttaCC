-- Standalone diagnostic probe tests. Never writes redstone.
local oldEpoch=os.epoch
local oldStartTimer=os.startTimer
local ms=1000000
local nextId=0
local logs={}
os.epoch=function() return ms end
os.startTimer=function(seconds)
    assert(seconds==1,"probe must sample once per second")
    nextId=nextId+1
    return nextId
end
local function run()
    local age=0
    local app={log=function(_,level,message)
        logs[#logs+1]={level=level,message=message}
    end}
    local controller={snapshot=function()
        return {lastUpdateAgeMs=age}
    end}
    local probe=dofile("apps/elevator/diagnostics.lua").new(app,controller)
    assert(probe:snapshot()=="NOT STARTED")
    probe:start()
    assert(probe:snapshot()=="0 ticks; last 0 ms ago")
    assert(probe:onTimer(999)==false)
    assert(nextId==1,"other timers must be ignored")
    ms=ms+1000
    assert(probe:onTimer(1)==true)
    assert(probe:snapshot()=="1 ticks; last 0 ms ago")
    age=4000
    ms=ms+1000
    assert(probe:onTimer(2)==true)
    assert(#logs==1 and logs[1].message:find("controller updates stopped",1,true))
    ms=ms+1000
    assert(probe:onTimer(3)==true)
    assert(#logs==1,"do not flood logs during a stall")
    age=50
    ms=ms+1000
    assert(probe:onTimer(4)==true)
    age=3500
    ms=ms+1000
    assert(probe:onTimer(5)==true)
    assert(#logs==2,"warning can recur after controller recovers")
end
local ok,err=pcall(run)
os.epoch=oldEpoch
os.startTimer=oldStartTimer
if not ok then error(err,0) end
print("Elevator isolated timer diagnostics: OK")
