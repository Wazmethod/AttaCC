-- Application-local timer probe: observes whether CraftOS keeps delivering
-- timer events after Elevator's SDK periodic controller updates stop.
-- Does not read/write any redstone or change controller scheduling.
local M={}
function M.new(app,controller)
    local id=nil
    local ticks=0
    local lastAt=nil
    local warned=false
    local function now() return os.epoch("utc") end
    local self={}
    function self:start()
        id=os.startTimer(1)
        ticks=0
        lastAt=now()
        warned=false
    end
    function self:onTimer(firedId)
        if not id or firedId~=id then return false end
        ticks=ticks+1
        lastAt=now()
        -- The SDK host ignores non-matching timer IDs; this application
        -- handler receives only the timer created above.
        id=os.startTimer(1)
        local state=controller.snapshot()
        if (state.lastUpdateAgeMs or 0)>3000 and not warned then
            warned=true
            app:log("warning","Elevator probe: timer events continue but "..
                "controller updates stopped for "..state.lastUpdateAgeMs.." ms")
        elseif (state.lastUpdateAgeMs or 0)<1000 then
            warned=false
        end
        return true
    end
    function self:snapshot()
        if not id then return "NOT STARTED" end
        return ticks.." ticks; last "..math.max(0,now()-(lastAt or now())).." ms ago"
    end
    return self
end
return M
