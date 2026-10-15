-- SteamPlant native SDK I/O service: no internal framework imports.
-- Hardware roles are declared in this application's requirements.lua.
local M={}
function M.setup(app)
    local state={main=nil,alternator=nil,gen=nil,motorRPM=nil}
    local roles={main="main_clutch",alternator="alternator_clutch",gen="gen_clutch"}
    local function clutch(name,value)
        local role=roles[name]
        if not role then return false,"unknown clutch" end
        if type(value)~="boolean" then return false,"clutch value must be boolean" end
        local output,err=app:output(role)
        if not output then return false,err end
        local ok,reason=output:set(value)
        if ok==false or (ok==nil and reason) then return false,reason end
        state[name]=value
        return true
    end
    local function engaged(name)
        local value,err=app:read(roles[name])
        if err then return nil,err end
        return value==true
    end
    local function speed(rpm)
        rpm=tonumber(rpm)
        if not rpm or rpm~=rpm or rpm==math.huge or rpm==-math.huge then
            return false,"invalid motor RPM"
        end
        local direction=tonumber(app:config("motor.direction",1)) or 1
        direction=direction<0 and -1 or 1
        local physical=rpm*direction
        local _,err
        if physical==0 then _,err=app:call("motor","stop")
        else _,err=app:call("motor","setSpeed",physical) end
        if err then return false,err end
        state.motorRPM=rpm
        return true
    end
    local service={
        refresh=function()
            local results,ready=app:hardwareStatus()
            return ready,results
        end,
        call=function(_,role,method,fallback,...)
            local value,err=app:call(role,method,...)
            if err or value==nil then return fallback end
            return value
        end,
        setMain=function(value) return clutch("main",value) end,
        setAlternator=function(value) return clutch("alternator",value) end,
        setGen=function(value) return clutch("gen",value) end,
        mainEngaged=function() return engaged("main") end,
        alternatorEngaged=function() return engaged("alternator") end,
        genEngaged=function() return engaged("gen") end,
        getSpeed=function() local value=app:call("speedometer","getSpeed");return value or 0 end,
        setMotorSpeed=speed,
        stopMotor=function() return speed(0) end,
        getOutputState=function()
            return {main=state.main,alternator=state.alternator,
                gen=state.gen,motorRPM=state.motorRPM}
        end,
    }
    return service
end
return M
