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
    local preparingMs=nil
    local releaseTimerId=nil
    local updates=0
    local lastUpdateAt=nil
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
    -- A/B diagnostic only: cache inputs after boot if and only if read-only
    -- commissioning is enabled. No motor control is permitted in this mode.
    local skipInputPolling=app:config("diagnostics.skipInputPolling",false)==true
    local eventInputs=app:config("diagnostics.bridgeEvents",false)==true
    local watchRoutes={}

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
    -- An opt-in commissioning path for bridges which provide the CC:
    -- Create redstone_link_change event. All five inputs must be bridged.
    -- This is intentionally READ-ONLY until real-world safety is validated.
    local function setupEventInputs()
        if not eventInputs then return true end
        if app:config("motion.readOnly",false)~=true then
            return false,"bridgeEvents requires motion.readOnly=true"
        end
        if skipInputPolling then
            return false,"bridgeEvents conflicts with skipInputPolling"
        end
        local registry=require("lib.io_registry")
        local routes={}
        for _,role in ipairs(roles) do
            local binding=registry.describe("elevator."..role)
            if type(binding)~="table" or
                binding.driver~="create.redstone_link" or
                type(binding.peripheral)~="string" then
                return false,"event mode requires a Redstone Link Bridge for "..role
            end
            if not peripheral.isPresent(binding.peripheral) then
                return false,"event Bridge missing for "..role
            end
            local canWatch=false
            for _,method in ipairs(peripheral.getMethods(binding.peripheral) or {}) do
                if method=="watchLinkSignal" then canWatch=true;break end
            end
            if not canWatch then
                return false,"Bridge does not expose watchLinkSignal: "..binding.peripheral
            end
            local key=tostring(binding.freq1).."|"..tostring(binding.freq2)..
                "|" .. tostring(binding.color1).."|"..tostring(binding.color2)
            if routes[key] then
                return false,"two inputs share the same watched Redstone Link frequency"
            end
            routes[key]={role=role,invert=binding.invert==true}
        end
        watchRoutes=routes
        return true
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
    local function cancelReleaseTimer()
        if releaseTimerId then
            os.cancelTimer(releaseTimerId)
            releaseTimerId=nil
        end
    end
    local function errorState(reason)
        cancelReleaseTimer()
        reason=tostring(reason)
        local changed=phase~="ERROR" or lastError~=reason
        halt()
        phase="ERROR"
        lastError=reason
        destination=nil
        startedAt=nil
        releaseAt=nil
        preparingMs=nil
        if changed then event("ELEVATOR_ERROR",lastError,"error") end
        return false,lastError
    end
    local function arrived(floor)
        cancelReleaseTimer()
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
        preparingMs=nil
        lastError="-"
        if wasTravelling then
            tripCount=tripCount+1
            local saved,saveErr=app:state("trips",{count=tripCount})
            if not saved then app:log("warning","trip count: "..tostring(saveErr)) end
            event("ELEVATOR_ARRIVED",floor.." reached (request "..tostring(target)..")")
        end
    end
    -- Called either by the regular SDK poll or by Elevator's own one-shot
    -- timer. The release is time-based, NOT tied to a button going LOW.
    local function advancePreparing()
        if phase~="PREPARING" or not releaseAt or not destination then return false end
        local stamp=now()
        local elapsed=stamp-(startedAt or stamp)
        if elapsed>5000 then
            return errorState("preparing stalled for "..elapsed.." ms; Clutch held")
        end
        if stamp<releaseAt then return false end
        local ok,err=write("clutch",false)
        if not ok then return errorState(err) end
        cancelReleaseTimer()
        phase="MOVING"
        releaseAt=nil
        preparingMs=nil
        event("ELEVATOR_MOVING","moving to "..destination)
        return true
    end
    local function request(floor,source)
        if floor~="TOP" and floor~="BOTTOM" then return false,"invalid floor" end
        if app:config("motion.readOnly",false)==true then
            return false,"commissioning read-only: movements disabled"
        end
        if phase=="ERROR" then return false,"controller in ERROR; use STOP to reset" end
        -- The SDK's main timer can stop being delivered while mouse clicks
        -- remain responsive. Never accept a movement request if the sensor
        -- polling is already stale: without fresh ticks PREPARING cannot
        -- transition safely or verify arrival contacts.
        local pollSeconds=tonumber(app:config("motion.pollInterval",0.15)) or 0.15
        local maxAge=math.max(2000,5*math.max(0.05,pollSeconds)*1000)
        if not lastUpdateAt or now()-lastUpdateAt>maxAge then
            local stopped,stopErr=halt()
            if not stopped then return errorState(stopErr) end
            app:log("warning","Elevator request blocked: controller updates stale")
            return false,"controller updates stale; movement inhibited"
        end
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
        preparingMs=math.max(50,tonumber(app:config("motion.settleMs",250)) or 250)
        -- Never silently schedule a dangerously long automatic release.
        if preparingMs>5000 then
            return errorState("invalid motion.settleMs > 5000 ms")
        end
        startedAt=now()
        releaseAt=startedAt+preparingMs
        event("ELEVATOR_REQUEST",(source or "SDK").." requested "..floor)
        -- The SDK may poll inputs only every 500ms. A dedicated one-shot
        -- timer avoids waiting for another full five-Bridge-read cycle.
        -- Arm it after publishing the event so peripheral/network work
        -- cannot consume its delay before we even start listening.
        if app:config("motion.preciseReleaseTimer",true)~=false then
            local delay=math.max(0.05,(releaseAt-now())/1000)
            local armed,id=pcall(os.startTimer,delay)
            if not armed then
                return errorState("preparing timer unavailable: "..tostring(id))
            end
            releaseTimerId=id
        end
        return true
    end
    function M.boot()
        cancelReleaseTimer()
        local stopped,err=halt()
        if not stopped then return errorState(err) end
        local configured,configError=setupEventInputs()
        if not configured then return errorState(configError) end
        local values,readErr=readInputs()
        if not values then return errorState(readErr) end
        inputs=values
        for _,role in ipairs(roles) do previous[role]=values[role] end
        position=sense(values)
        if position=="CONFLICT" then return errorState("both floor sensors active") end
        lastFloor=position
        phase="IDLE"
        destination=nil
        preparingMs=nil
        updates=0
        lastUpdateAt=now()
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
        cancelReleaseTimer()
        return halt()
    end
    function M.stop()
        cancelReleaseTimer()
        local ok,err=halt()
        if not ok then return errorState(err) end
        destination=nil
        phase="IDLE"
        startedAt=nil
        releaseAt=nil
        preparingMs=nil
        lastError="-"
        position=sense(inputs)
        if position=="UNKNOWN" then lastFloor="UNKNOWN" end
        event("ELEVATOR_STOP","movement stopped")
        return true
    end
    function M.onLinkChange(freq1,freq2,strength,color1,color2)
        if not eventInputs or app:config("motion.readOnly",false)~=true then return false end
        if type(strength)~="number" then return false end
        local key=tostring(freq1).."|"..tostring(freq2)..
            "|" .. tostring(color1).."|"..tostring(color2)
        local route=watchRoutes[key]
        if not route then return false end
        local value=strength>0
        if route.invert then value=not value end
        inputs[route.role]=value
        return true
    end
    -- The SDK forwards only application timer events here; its main timer
    -- remains owned by the unmodified shared host.
    function M.onTimer(timerId)
        if not releaseTimerId or timerId~=releaseTimerId then return false end
        releaseTimerId=nil
        if phase~="PREPARING" or not destination or not releaseAt then return true end
        if app:config("motion.readOnly",false)==true then
            return errorState("read-only enabled during preparation; Clutch held")
        end
        local poll=tonumber(app:config("motion.pollInterval",0.15)) or 0.15
        local maxAge=math.max(1000,3*math.max(0.05,poll)*1000)
        if not lastUpdateAt or now()-lastUpdateAt>maxAge then
            return errorState("controller updates stale during preparation; Clutch held")
        end
        if now()<releaseAt then
            -- CraftOS timers are approximate. Never release earlier than
            -- motion.settleMs, even if a timer arrives slightly early.
            releaseTimerId=os.startTimer(math.max(0.05,(releaseAt-now())/1000))
            return true
        end
        return advancePreparing()
    end
    function M.update()
        updates=updates+1
        lastUpdateAt=now()
        local values,readErr
        if (skipInputPolling or eventInputs)
            and app:config("motion.readOnly",false)==true then
            -- Inputs were sampled once at boot. Do not call the Bridge
            -- inside the periodic timer during this read-only A/B test.
            values=inputs
        else
            values,readErr=readInputs()
        end
        if not values then return errorState(readErr) end
        inputs=values
        local here=sense(values)
        if here=="CONFLICT" then return errorState("both floor sensors active") end
        if destination and here==destination then
            arrived(here)
        elseif phase=="PREPARING" and releaseAt then
            local prepared,prepareError=advancePreparing()
            if prepareError then return false,prepareError end
        elseif destination and startedAt and now()-startedAt>
            math.max(5000,(tonumber(app:config("motion.timeoutSeconds",120)) or 120)*1000) then
            return errorState("travel timeout to "..destination)
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
        local stamp=now()
        return {phase=phase,position=position,destination=destination or "-",
            updates=updates,
            lastUpdateAgeMs=lastUpdateAt and math.max(0,stamp-lastUpdateAt) or -1,
            preparingElapsedMs=phase=="PREPARING" and startedAt and math.max(0,stamp-startedAt) or nil,
            preparingRemainingMs=phase=="PREPARING" and releaseAt and math.max(0,releaseAt-stamp) or nil,
            preparingDelayMs=preparingMs,
            error=lastError,trips=tripCount,top=inputs.at_top==true,
            bottom=inputs.at_bottom==true,callTop=inputs.call_top==true,
            callBottom=inputs.call_bottom==true,callCabin=inputs.call_cabin==true,
            clutchStopped=phase~="MOVING",lastFloor=lastFloor}
    end
    return M
end
return M
