-- SDK HID: separate terminal text and external monitor touch surfaces.
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
    function self:handle(event,a,b,c)
        if event=="monitor_touch" then
            if not self.monitorName or a~=self.monitorName then return false end
            if self.monitor then
                local x,y=b,c
                if self.monitor.backend=="ccgraphics" then
                    -- monitor_touch coordinates are text cells; CC:Graphics
                    -- hitboxes use 0-based pixel coordinates.
                    local monitor=peripheral.wrap(a)
                    if not monitor then return false end
                    local ok,tw,th=pcall(monitor.getSize,0)
                    if not ok or type(tw)~="number" or type(th)~="number"
                       or tw<1 or th<1 then return false end
                    x=math.floor((b-0.5)*self.monitor.width/tw)
                    y=math.floor((c-0.5)*self.monitor.height/th)
                end
                return app:touch(self.monitor,x,y)
            end
            return false
        elseif event=="mouse_click" then
            if self.terminal then
                if self.terminalMode=="maintenance" then return app:maintenanceTouch(self.terminal,b,c) end
                return app:touch(self.terminal,b,c)
            end
            return false
        elseif event=="key" then
            if type(options.keys)=="table" then
                local control=options.keys[a]
                if type(control)=="string" then return app:invoke(control) end
            end
        end
        return false
    end
    return self
end
return M
