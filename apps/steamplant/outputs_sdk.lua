-- SteamPlant native SDK I/O service: no internal framework imports.
-- Hardware roles are declared in this application's requirements.lua.
local M={}
function M.setup(app)
    local state={main=nil,alternator=nil,gen=nil,motorRPM=nil}
    local roles={main="main_clutch",alternator="alternator_clutch",gen="gen_clutch"}
    local function persist()
        if type(state.main)~="boolean" or type(state.alternator)~="boolean"
          or type(state.gen)~="boolean" or type(state.motorRPM)~="number" then
            return false,"incomplete output state"
        end
        return app:state("outputs",state)
    end
    local function clutch(name,value,save)
        local role=roles[name]
        if not role then return false,"unknown clutch" end
        if type(value)~="boolean" then return false,"clutch value must be boolean" end
        local output,err=app:output(role)
        if not output then return false,err end
        local ok,reason=output:set(value)
        if ok==false or (ok==nil and reason) then return false,reason end
        state[name]=value
        if save~=false and state.motorRPM~=nil and state.main~=nil
          and state.alternator~=nil and state.gen~=nil then return persist() end
        return true
    end
    local function engaged(name)
        local value,err=app:read(roles[name])
        if err then return nil,err end
        return value==true
    end
    local function speed(rpm,save)
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
        if save~=false and state.main~=nil and state.alternator~=nil
          and state.gen~=nil then return persist() end
        return true
    end
    local service={
        refresh=function()
            local results,ready=app:hardwareStatus()
            return ready,results
        end,
        call=function(role,method,fallback,...)
            local value,err=app:call(role,method,...)
            if err or value==nil then return fallback end
            return value
        end,
        setMain=function(value,save) return clutch("main",value,save) end,
        setAlternator=function(value,save) return clutch("alternator",value,save) end,
        setGen=function(value,save) return clutch("gen",value,save) end,
        mainEngaged=function() return engaged("main") end,
        alternatorEngaged=function() return engaged("alternator") end,
        genEngaged=function() return engaged("gen") end,
        getSpeed=function() local value=app:call("speedometer","getSpeed");return value or 0 end,
        setMotorSpeed=speed,
        stopMotor=function(save) return speed(0,save) end,
        restoreOutputs=function()
            local loaded=app:state("outputs")
            local source="persisted"
            if type(loaded)~="table" or type(loaded.main)~="boolean"
              or type(loaded.alternator)~="boolean" or type(loaded.gen)~="boolean"
              or type(loaded.motorRPM)~="number" then
                source="config"
                local function boot(name)
                    local setting=app:config("bootState."..name)
                    if setting=="engaged" then return true end
                    if setting=="cut" then return false end
                    return nil
                end
                loaded={main=boot("main"),alternator=boot("alternator"),
                    gen=boot("gen"),motorRPM=tonumber(app:config("bootState.motorRPM",0))}
            end
            if type(loaded.main)~="boolean" or type(loaded.alternator)~="boolean"
              or type(loaded.gen)~="boolean" or type(loaded.motorRPM)~="number" then
                return false,"invalid boot outputs",source
            end
            for _,name in ipairs({"main","alternator","gen"}) do
                local ok,err=clutch(name,loaded[name],false)
                if not ok then return false,err,source end
            end
            local ok,err=speed(loaded.motorRPM,false)
            if not ok then return false,err,source end
            local saved,saveErr=persist()
            if not saved then return false,saveErr,source end
            return true,nil,source
        end,
        getOutputState=function()
            return {main=state.main,alternator=state.alternator,
                gen=state.gen,motorRPM=state.motorRPM}
        end,
    }
    return service
end
return M
