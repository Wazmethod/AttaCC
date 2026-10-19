-- Two-floor gantry controller. No Create-specific peripheral/API required.
-- All physical IO goes through the SDK declared bindings (including relays).
local M={}
function M.new(app)
    local phase="IDLE"
    local position="UNKNOWN"
    local destination=nil
    local lastError="-"
    local lastFloor="UNKNOWN"
    local startedAt=nil
    local releaseAt=nil
    -- SDK state() returns a JSON table on success, or nil + an error
    -- (for instance "missing"). Store the first return value separately:
    -- tonumber(app:state(...)) would interpret that error as a numeric base.
    local storedTrips=app:state("trips")
    local tripCount=0
    if type(storedTrips)=="table" then
        tripCount=tonumber(storedTrips.count or storedTrips.trips) or 0
    elseif type(storedTrips)=="number" or type(storedTrips)=="string" then
        -- Tolerate older test installations which stored a scalar.
        tripCount=tonumber(storedTrips) or 0
    end
    local inputs={}
    local previous={}
    local now=function() return os.epoch("utc") end

    local roles={"call_top","call_bottom","call_cabin","at_top","at_bottom"}
    local function event(code,message,level)
        local item={code=code,message=message,level=level or "info"}
        app:emit("elevator.event",item)
        if app.networkTransport then
            local sent,err=app:publishNetwork("app.event",item)
            if not sent then app:log("warning","event: "..tostring(err)) end
        end
        app:log(level or "info",code..": "..message)
    end
    local function readInputs()
        local values={}
        for _,role in ipairs(roles) do
            local value,err=app:read(role)
            if err then return nil,role..": "..tostring(err) end
            values[role]=value==true
        end
        return values
    end
    local function sense(values)
        if values.at_top and values.at_bottom then return "CONFLICT" end
        if values.at_top then return "TOP" end
        if values.at_bottom then return "BOTTOM" end
        return "UNKNOWN"
    end
    local function write(role,value)
        local ok,err=app:write(role,value)
        if not ok then return false,role..": "..tostring(err) end
        return true
    end
    local function halt()
        -- A Create clutch stops transmitting rotation while powered.
        return write("clutch",true)
    end
    local function errorState(reason)
        reason=tostring(reason)
        local changed=phase~="ERROR" or lastError~=reason
        halt()
        phase="ERROR"
        lastError=reason
        destination=nil
        startedAt=nil
        releaseAt=nil
        if changed then event("ELEVATOR_ERROR",lastError,"error") end
        return false,lastError
    end
    local function arrived(floor)
        local ok,err=halt()
        if not ok then return errorState(err) end
        local wasTravelling=destination~=nil
        local target=destination
        position=floor
        lastFloor=floor
        phase="IDLE"
        destination=nil
        startedAt=nil
        releaseAt=nil
        lastError="-"
        if wasTravelling then
            tripCount=tripCount+1
            local saved,saveErr=app:state("trips",{count=tripCount})
            if not saved then app:log("warning","trip count: "..tostring(saveErr)) end
            event("ELEVATOR_ARRIVED",floor.." reached (request "..tostring(target)..")")
        end
    end
    local function request(floor,source)
        if floor~="TOP" and floor~="BOTTOM" then return false,"invalid floor" end
        if phase=="ERROR" then return false,"controller in ERROR; use STOP to reset" end
        if destination then
            if destination==floor then return true end
            return false,"elevator busy moving to "..destination
        end
        local here=sense(inputs)
        if here=="CONFLICT" then return errorState("both floor sensors active") end
        if here=="UNKNOWN" and phase=="IDLE" then here=lastFloor end
        if here==floor then
            position=floor
            phase="IDLE"
            return true
        end
        -- Stop before changing Gearshift polarity. Release after settling.
        local stopped,stopErr=halt()
        if not stopped then return errorState(stopErr) end
        local reverseForUp=app:config("motion.reverseForUp",false)==true
        local reverse
        if floor=="TOP" then reverse=reverseForUp
        else reverse=not reverseForUp end
        local shifted,shiftErr=write("gearshift",reverse)
        if not shifted then return errorState(shiftErr) end
        destination=floor
        position=here
        phase="PREPARING"
        startedAt=now()
        releaseAt=now()+math.max(50,tonumber(app:config("motion.settleMs",250)) or 250)
        event("ELEVATOR_REQUEST",(source or "SDK").." requested "..floor)
        return true
    end
    function M.boot()
        local stopped,err=halt()
        if not stopped then return errorState(err) end
        local values,readErr=readInputs()
        if not values then return errorState(readErr) end
        inputs=values
        for _,role in ipairs(roles) do previous[role]=values[role] end
        position=sense(values)
        if position=="CONFLICT" then return errorState("both floor sensors active") end
        lastFloor=position
        phase="IDLE"
        destination=nil
        lastError="-"
        event("ELEVATOR_READY","at "..position)
        return true
    end
    function M.request(floor,source) return request(floor,source) end
    function M.cabin()
        -- Contacts may be momentary at the end of a gantry journey.
        local here=sense(inputs)
        if here=="UNKNOWN" and phase=="IDLE" then here=lastFloor end
        if here=="TOP" then return request("BOTTOM","CABIN") end
        if here=="BOTTOM" then return request("TOP","CABIN") end
        return false,"cabin destination unknown; use TOP or BOTTOM"
    end
    -- A normal SDK shutdown must not leave the gantry powered.
    function M.shutdown()
        return halt()
    end
    function M.stop()
        local ok,err=halt()
        if not ok then return errorState(err) end
        destination=nil
        phase="IDLE"
        startedAt=nil
        releaseAt=nil
        lastError="-"
        position=sense(inputs)
        if position=="UNKNOWN" then lastFloor="UNKNOWN" end
        event("ELEVATOR_STOP","movement stopped")
        return true
    end
    function M.update()
        local values,readErr=readInputs()
        if not values then return errorState(readErr) end
        inputs=values
        local here=sense(values)
        if here=="CONFLICT" then return errorState("both floor sensors active") end
        if destination and here==destination then
            arrived(here)
        elseif destination and startedAt and now()-startedAt>
            math.max(5000,(tonumber(app:config("motion.timeoutSeconds",120)) or 120)*1000) then
            return errorState("travel timeout to "..destination)
        elseif phase=="PREPARING" and releaseAt and now()>=releaseAt then
            local ok,err=write("clutch",false)
            if not ok then return errorState(err) end
            phase="MOVING"
            releaseAt=nil
            event("ELEVATOR_MOVING","moving to "..destination)
        end
        if not destination and phase=="IDLE" then
            if here=="TOP" or here=="BOTTOM" then
                position=here
                lastFloor=here
            else
                position=lastFloor
            end
        end
        -- Short redstone pulses become one request per rising edge.
        -- Cabin Redstone Link can transmit only while the contraption is stationary.
        for _,entry in ipairs({
            {"call_top","TOP"},{"call_bottom","BOTTOM"},{"call_cabin","CABIN"}
        }) do
            local role,floor=entry[1],entry[2]
            if values[role] and not previous[role] then
                if floor=="CABIN" then M.cabin() else request(floor,role) end
            end
        end
        for _,role in ipairs(roles) do previous[role]=values[role] end
        return true
    end
    function M.snapshot()
        return {phase=phase,position=position,destination=destination or "-",
            error=lastError,trips=tripCount,top=inputs.at_top==true,
            bottom=inputs.at_bottom==true,callTop=inputs.call_top==true,
            callBottom=inputs.call_bottom==true,callCabin=inputs.call_cabin==true,
            clutchStopped=phase~="MOVING",lastFloor=lastFloor}
    end
    return M
end
return M
