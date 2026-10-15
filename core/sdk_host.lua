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
    local published,err=app:publish()
    if not published then return false,err end
    app:status("active","SDK application running")
    local interval=tonumber(options.interval) or 1
    if interval<0.05 then interval=0.05 end
    local running=true
    local timer=os.startTimer(interval)
    local render=options.display~=false
    local lastDraw=nil
    local function redraw()
        if not render then return end
        local ok,result=pcall(function() return app:draw(options.target) end)
        if ok then lastDraw=result
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
                    if not updateOk then app:log("error","update: "..tostring(updateError)) end
                end
                dispatch("tick")
                local success,pubErr=app:publish()
                if not success then app:log("warning","publish failed: "..tostring(pubErr)) end
                redraw()
                timer=os.startTimer(interval)
            elseif name=="monitor_touch" or name=="mouse_click" then
                if lastDraw then
                    local x,y=name=="monitor_touch" and e[3] or e[3],
                        name=="monitor_touch" and e[4] or e[4]
                    local touched,reason=app:touch(lastDraw,x,y)
                    if touched then redraw() end
                end
                dispatch(name,table.unpack(e,2))
            else dispatch(name,table.unpack(e,2)) end
        end
    end,function(e) return tostring(e) end)
    app:close()
    if not ok then return false,issue end
    return true
end
return M
