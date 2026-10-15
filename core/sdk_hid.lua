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
            -- The current CC:Graphics monitor reports pixel positions directly.
            -- Do not rescale into text cells or try two conflicting hitboxes.
            if not hit(result,b,c) then return false,"touch misses graphics hitboxes" end
            return app:touch(result,b,c)
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
