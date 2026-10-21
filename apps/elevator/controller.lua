-- Simple two-floor Create elevator: three buttons, two contacts, two outputs.
-- All I/O continues to use the SDK bindings defined by ioctl.
local M={}

function M.new(app)
    local phase="IDLE"
    local floor="UNKNOWN"
    local lastFloor="UNKNOWN"
    local target=nil
    local startedAt=nil
    local dueAt=nil
    local releaseTimer=nil
    local lastPoll=nil
    local polls=0
    local err="-"
    local inputs={}
    local previous={}
    local roles={"call_top","call_bottom","call_cabin","at_top","at_bottom"}
    local now=function() return os.epoch("utc") end

    local stored=app:state("trips")
    local trips=type(stored)=="table" and (tonumber(stored.count) or 0) or 0

    local function log(code,message,level)
        app:emit("elevator.event",{code=code,message=message,level=level or "info"})
        app:log(level or "info",code..": "..message)
    end
    local function cancelTimer()
        if releaseTimer then os.cancelTimer(releaseTimer);releaseTimer=nil end
    end
    local function stopDrive()
        -- Create Clutch: ON cuts transmission, OFF lets it turn.
        return app:write("clutch",true)
    end
    local function position(values)
        if values.at_top and values.at_bottom then return "CONFLICT" end
        if values.at_top then return "TOP" end
        if values.at_bottom then return "BOTTOM" end
        return "UNKNOWN"
    end
    local function readInputs()
        local values={}
        for _,role in ipairs(roles) do
            local value,readErr=app:read(role)
            if readErr then return nil,role..": "..tostring(readErr) end
            values[role]=value==true
        end
        return values
    end
    local function fail(reason)
        cancelTimer()
        local stopped,stopErr=stopDrive()
        if not stopped then reason=tostring(reason).."; stop failed: "..tostring(stopErr) end
        local changed=phase~="ERROR" or err~=tostring(reason)
        phase="ERROR"
        target=nil
        startedAt=nil
        dueAt=nil
        err=tostring(reason)
        if changed then log("ELEVATOR_ERROR",err,"error") end
        return false,err
    end
    local function arrived(here)
        cancelTimer()
        local ok,stopErr=stopDrive()
        if not ok then return fail(stopErr) end
        local completed=target~=nil
        floor=here
        lastFloor=here
        phase="IDLE"
        target=nil
        startedAt=nil
        dueAt=nil
        err="-"
        if completed then
            trips=trips+1
            local saved,saveErr=app:state("trips",{count=trips})
            if not saved then app:log("warning","trip count: "..tostring(saveErr)) end
            log("ELEVATOR_ARRIVED",here.." reached")
        end
        return true
    end
    local function startMoving()
        if phase~="PREPARING" or not dueAt then return false end
        if now()<dueAt then return false end
        if now()-(startedAt or now())>5000 then
            return fail("preparation delayed; Clutch held")
        end
        if app:config("motion.readOnly",false)==true then
            return fail("read-only during preparation; Clutch held")
        end
        local poll=tonumber(app:config("motion.pollInterval",0.5)) or 0.5
        if not lastPoll or now()-lastPoll>math.max(2000,poll*4000) then
            return fail("sensor polling stale; Clutch held")
        end
        local ok,writeErr=app:write("clutch",false)
        if not ok then return fail(writeErr) end
        cancelTimer()
        phase="MOVING"
        dueAt=nil
        log("ELEVATOR_MOVING","moving to "..target)
        return true
    end
    local function request(destination,source)
        if destination~="TOP" and destination~="BOTTOM" then
            return false,"invalid floor"
        end
        if app:config("motion.readOnly",false)==true then
            return false,"read-only: movement disabled"
        end
        if phase=="ERROR" then return false,"controller in ERROR; use STOP" end
        if target then
            if target==destination then return true end
            return false,"already moving to "..target
        end
        local poll=tonumber(app:config("motion.pollInterval",0.5)) or 0.5
        if not lastPoll or now()-lastPoll>math.max(2000,poll*4000) then
            return false,"sensor polling stale; movement inhibited"
        end
        local here=position(inputs)
        if here=="CONFLICT" then return fail("both floor contacts active") end
        if here=="UNKNOWN" then here=lastFloor end
        if here==destination then return true end

        local ok,stopErr=stopDrive()
        if not ok then return fail(stopErr) end
        local reverseForUp=app:config("motion.reverseForUp",false)==true
        local reverse=(destination=="TOP") == reverseForUp
        local shifted,shiftErr=app:write("gearshift",reverse)
        if not shifted then return fail(shiftErr) end

        local settle=tonumber(app:config("motion.settleMs",250)) or 250
        if settle<50 or settle>5000 then return fail("invalid motion.settleMs") end
        target=destination
        phase="PREPARING"
        startedAt=now()
        dueAt=startedAt+settle
        -- One small timer to free the Clutch after Gearshift settles.
        -- It does NOT wait for the button to return to OFF.
        releaseTimer=os.startTimer(math.max(0.05,settle/1000))
        log("ELEVATOR_REQUEST",(source or "SDK").." requested "..destination)
        return true
    end

    function M.boot()
        cancelTimer()
        local ok,stopErr=stopDrive()
        if not ok then return fail(stopErr) end
        local values,readErr=readInputs()
        if not values then return fail(readErr) end
        inputs=values
        for _,role in ipairs(roles) do previous[role]=values[role] end
        floor=position(values)
        if floor=="CONFLICT" then return fail("both floor contacts active") end
        lastFloor=floor
        phase="IDLE"
        target=nil
        startedAt=nil
        dueAt=nil
        lastPoll=now()
        polls=0
        err="-"
        log("ELEVATOR_READY","at "..floor)
        return true
    end
    function M.request(destination,source) return request(destination,source) end
    function M.cabin()
        local here=position(inputs)
        if here=="UNKNOWN" then here=lastFloor end
        if here=="TOP" then return request("BOTTOM","CABIN") end
        if here=="BOTTOM" then return request("TOP","CABIN") end
        return false,"cabin floor unknown"
    end
    function M.stop()
        cancelTimer()
        local ok,stopErr=stopDrive()
        if not ok then return fail(stopErr) end
        target=nil
        startedAt=nil
        dueAt=nil
        phase="IDLE"
        err="-"
        local here=position(inputs)
        floor=here=="UNKNOWN" and lastFloor or here
        log("ELEVATOR_STOP","stopped")
        return true
    end
    function M.shutdown()
        cancelTimer()
        return stopDrive()
    end
    function M.onTimer(id)
        if not releaseTimer or id~=releaseTimer then return false end
        releaseTimer=nil
        if phase~="PREPARING" then return true end
        if now()<dueAt then
            releaseTimer=os.startTimer(math.max(0.05,(dueAt-now())/1000))
            return true
        end
        return startMoving()
    end
    function M.update()
        local values,readErr=readInputs()
        if not values then return fail(readErr) end
        lastPoll=now()
        polls=polls+1
        inputs=values
        local here=position(values)
        if here=="CONFLICT" then return fail("both floor contacts active") end
        if target and here==target then
            local ok,arrivalErr=arrived(here)
            if not ok then return false,arrivalErr end
        elseif phase=="PREPARING" then
            local ok,prepareErr=startMoving() -- Fallback if its timer was lost.
            if prepareErr then return false,prepareErr end
        elseif phase=="MOVING" then
            local timeout=(tonumber(app:config("motion.timeoutSeconds",120)) or 120)*1000
            if startedAt and now()-startedAt>timeout then
                return fail("travel timeout to "..target)
            end
        end
        if phase=="IDLE" then
            if here~="UNKNOWN" then floor=here;lastFloor=here end
        end
        -- Rising-edge detection for ALL THREE call buttons.
        for _,entry in ipairs({
            {"call_top","TOP"},{"call_bottom","BOTTOM"},{"call_cabin","CABIN"}
        }) do
            local role,destination=entry[1],entry[2]
            if values[role] and not previous[role] then
                if destination=="CABIN" then M.cabin()
                else request(destination,role) end
            end
        end
        for _,role in ipairs(roles) do previous[role]=values[role] end
        return true
    end
    function M.snapshot()
        local t=now()
        return {
            phase=phase,position=floor,destination=target or "-",
            top=inputs.at_top==true,bottom=inputs.at_bottom==true,
            callTop=inputs.call_top==true,callBottom=inputs.call_bottom==true,
            callCabin=inputs.call_cabin==true,clutchStopped=phase~="MOVING",
            trips=trips,error=err,polls=polls,
            lastPollAgeMs=lastPoll and math.max(0,t-lastPoll) or -1,
            preparingRemainingMs=dueAt and math.max(0,dueAt-t) or nil,
        }
    end
    return M
end
return M
