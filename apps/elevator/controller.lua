-- Simple two-floor Create elevator: three buttons, two contacts, two outputs.
-- All I/O continues to use the SDK bindings defined by ioctl.
local M={}

function M.new(app)
    local phase="IDLE"
    local floor="UNKNOWN"
    local lastFloor="UNKNOWN"
    local target=nil
    local startedAt=nil
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
        local stopped,stopErr=stopDrive()
        if not stopped then reason=tostring(reason).."; stop failed: "..tostring(stopErr) end
        local changed=phase~="ERROR" or err~=tostring(reason)
        phase="ERROR"
        target=nil
        startedAt=nil
        err=tostring(reason)
        if changed then log("ELEVATOR_ERROR",err,"error") end
        return false,err
    end
    local function arrived(here)
        local ok,stopErr=stopDrive()
        if not ok then return fail(stopErr) end
        local completed=target~=nil
        floor=here
        lastFloor=here
        phase="IDLE"
        target=nil
        startedAt=nil
        err="-"
        if completed then
            trips=trips+1
            local saved,saveErr=app:state("trips",{count=trips})
            if not saved then app:log("warning","trip count: "..tostring(saveErr)) end
            log("ELEVATOR_ARRIVED",here.." reached")
        end
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

        -- No extra timer or button-release dependency: Clutch stop,
        -- Gearshift direction, then Clutch release in this same scan.
        target=destination
        startedAt=now()
        local released,releaseErr=app:write("clutch",false)
        if not released then return fail(releaseErr) end
        phase="MOVING"
        log("ELEVATOR_MOVING",(source or "SDK").." requested "..destination)
        return true
    end

    function M.boot()
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
        local ok,stopErr=stopDrive()
        if not ok then return fail(stopErr) end
        target=nil
        startedAt=nil
        phase="IDLE"
        err="-"
        local here=position(inputs)
        -- If stopped between contacts, do not assume the carriage is
        -- still on its previous floor for the CABIN toggle button.
        floor=here
        lastFloor=here
        log("ELEVATOR_STOP","stopped")
        return true
    end
    function M.shutdown()
        return stopDrive()
    end
    function M.update()
        local wasMoving=phase=="MOVING"

        local function sample(role)
            local value,readErr=app:read(role)
            if readErr then return nil,role..": "..tostring(readErr) end
            inputs[role]=value==true
            return inputs[role]
        end
        local function contacts()
            -- During travel, detect the destination contact before polling
            -- anything else: stopping must take priority over call buttons.
            local top,topErr=sample("at_top")
            if top==nil then return fail(topErr) end
            local bottom,bottomErr=sample("at_bottom")
            if bottom==nil then return fail(bottomErr) end
            local here=position(inputs)
            if here=="CONFLICT" then return fail("both floor contacts active") end
            if target and here==target then
                local ok,arrivalErr=arrived(here)
                if not ok then return false,arrivalErr end
            elseif phase=="MOVING" then
                local timeout=(tonumber(app:config("motion.timeoutSeconds",120)) or 120)*1000
                if startedAt and now()-startedAt>timeout then
                    return fail("travel timeout to "..target)
                end
            end
            if phase=="IDLE" and here~="UNKNOWN" then
                floor=here
                lastFloor=here
            end
            return true
        end
        local function buttons()
            -- Dispatch each rising edge as soon as THIS input is read.
            -- No longer wait for the other Bridge frequencies first.
            for _,entry in ipairs({
                {"call_top","TOP"},{"call_bottom","BOTTOM"},{"call_cabin","CABIN"}
            }) do
                local role,destination=entry[1],entry[2]
                local pressed,readErr=sample(role)
                if pressed==nil then return fail(readErr) end
                if pressed and not previous[role] and not wasMoving then
                    if destination=="CABIN" then M.cabin()
                    else request(destination,role) end
                end
                previous[role]=pressed
            end
            return true
        end

        local ok,readErr
        if wasMoving then
            ok,readErr=contacts()
            if not ok then return false,readErr end
            ok,readErr=buttons()
        else
            -- At a stationary floor, prioritize the three call buttons.
            ok,readErr=buttons()
            if not ok then return false,readErr end
            ok,readErr=contacts()
        end
        if not ok then return false,readErr end
        lastPoll=now()
        polls=polls+1
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
        }
    end
    return M
end
return M
