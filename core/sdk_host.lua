-- Generic SDK host: owns the CraftOS loop for standalone SDK applications.
-- Future network/HID drivers are attached here, never in application main.lua.
local M={}
function M.run(app,options)
    options=options or {}
    local ready,missing=app:checkDependencies()
    if not ready then return false,"missing dependencies: "..table.concat(missing,", ") end
    local status,hardwareReady=app:hardwareStatus()
    if not hardwareReady then
        local missingRoles={}
        for _,role in ipairs(status) do
            if role.required and role.status~="OK" then missingRoles[#missingRoles+1]=role.id end
        end
        return false,"missing hardware: "..table.concat(missingRoles,", ")
    end
    local transport
    if options.network~=false then
        local service,transportError=require("lib.sdk_transport").new(app,options)
        if service then transport=service
        elseif options.networkRequired then return false,transportError end
    end
    if type(options.start)=="function" then
        local started,readyOrErr,detail=pcall(options.start,app)
        if not started then return false,"startup failed: "..tostring(readyOrErr) end
        if readyOrErr==false then return false,"startup rejected: "..tostring(detail) end
    end
    local published,err=app:publish()
    if not published then return false,err end
    app:status("active","SDK application running")
    local interval=tonumber(options.interval) or 1
    if interval<0.05 then interval=0.05 end
    local running=true
    local timer=os.startTimer(interval)
    local render=options.display~=false
    local hid=require("lib.sdk_hid").new(app,options)
    local function redraw()
        if not render then return end
        local ok,result=pcall(function() return app:draw(options.target) end)
        if ok then hid:setRender(result)
        else app:log("warning","SDK display unavailable: "..tostring(result)) end
    end
    redraw()
    local function dispatch(name,...)
        local handlers=options.handlers or {}
        local fn=handlers[name]
        if type(fn)=="function" then
            local ok,result=pcall(fn,app,...)
            if not ok then app:log("error","event "..name..": "..tostring(result)) end
        end
    end
    local ok,issue=xpcall(function()
        while running do
            local e={os.pullEventRaw()}
            local name=e[1]
            if name=="terminate" then running=false
            elseif name=="timer" and e[2]==timer then
                app:tick()
                if type(options.update)=="function" then
                    local updateOk,updateError=pcall(options.update,app)
                    if not updateOk then error("application update failed: "..tostring(updateError)) end
                end
                dispatch("tick")
                local success,pubErr=app:publish()
                if not success then app:log("warning","publish failed: "..tostring(pubErr)) end
                if transport then
                    local sent,sendErr=transport:publish()
                    if not sent then app:log("warning","network snapshot: "..tostring(sendErr)) end
                end
                redraw()
                timer=os.startTimer(interval)
            elseif name=="modem_message" then
                if transport then transport:handle(e[3],e[5]) end
                dispatch(name,table.unpack(e,2))
            elseif name=="monitor_touch" or name=="mouse_click" or name=="key" then
                local touched=hid:handle(name,table.unpack(e,2))
                if touched then redraw() end
                dispatch(name,table.unpack(e,2))
            else dispatch(name,table.unpack(e,2)) end
        end
    end,function(e) return tostring(e) end)
    app:close()
    if not ok then return false,issue end
    return true
end
return M
