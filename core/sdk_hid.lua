-- SDK HID: dedicated CraftOS text and monitor graphics routing.
local M={}
function M.new(app,options)
    options=options or {}
    local self={terminal=nil,monitor=nil,monitorName=options.monitorName}
    function self:setRender(result,surface)
        if surface=="monitor" then self.monitor=result
        else self.terminal=result;self.terminalMode=surface end
    end
    function self:setMonitor(name)
        self.monitorName=name
        self.monitor=nil
    end
    local function hit(result,x,y)
        for _,area in ipairs(result.hitboxes or {}) do
            if x>=area.x1 and x<=area.x2 and y>=area.y1 and y<=area.y2 then
                return area.id
            end
        end
    end
    function self:handle(event,a,b,c)
        if event=="monitor_touch" then
            if not self.monitorName then return false,"no selected monitor" end
            if a~=self.monitorName then return false,"other monitor: "..tostring(a) end
            local result=self.monitor
            if not result or not result.ok then return false,"monitor has no valid render" end
            if type(b)~="number" or type(c)~="number" then return false,"invalid touch coordinates" end
            if result.backend~="ccgraphics" then
                return app:touch(result,b,c)
            end
            -- CC:Graphics monitor implementations may report coordinates in
            -- pixels or terminal cells. Resolve the hit BEFORE executing any
            -- control; ambiguous matches must never trigger a physical command.
            local candidates={{x=b,y=c,mode="pixel"}}
            local monitor=peripheral.wrap(a)
            if monitor and type(result.width)=="number" and type(result.height)=="number" then
                local ok,tw,th=pcall(monitor.getSize,0)
                if ok and type(tw)=="number" and type(th)=="number" and tw>0 and th>0 then
                    candidates[#candidates+1]={
                        x=math.floor((b-0.5)*result.width/tw),
                        y=math.floor((c-0.5)*result.height/th),mode="cell"
                    }
                end
            end
            local matched,choice
            for _,candidate in ipairs(candidates) do
                local id=hit(result,candidate.x,candidate.y)
                if id then
                    if matched and matched~=id then
                        -- A renderer toggle is safe to prioritize over a conflicting
                        -- coordinate interpretation. Never guess on hardware actions.
                        if id=="display.toggle" then
                            matched=id
                            choice=candidate
                        elseif matched~="display.toggle" then
                            return false,"ambiguous touch coordinates (pixel/cell)"
                        end
                    else
                        matched=id
                        choice=candidate
                    end
                end
            end
            if not choice then return false,"touch misses graphics hitboxes" end
            return app:touch(result,choice.x,choice.y)
        elseif event=="mouse_click" then
            if self.terminal then
                if self.terminalMode=="maintenance" then
                    return app:maintenanceTouch(self.terminal,b,c)
                end
                return app:touch(self.terminal,b,c)
            end
            return false,"terminal has no render"
        elseif event=="key" and type(options.keys)=="table" then
            local control=options.keys[a]
            if type(control)=="string" then return app:invoke(control) end
        end
        return false
    end
    return self
end
return M
