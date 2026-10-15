-- SDK HID: separate terminal text and external monitor touch surfaces.
local M={}
function M.new(app,options)
    options=options or {}
    local self={terminal=nil,monitor=nil,monitorName=options.monitorName}
    function self:setRender(result,surface)
        if surface=="monitor" then self.monitor=result
        else self.terminal=result end
    end
    function self:setMonitor(name)
        self.monitorName=name
        self.monitor=nil
    end
    function self:handle(event,a,b,c)
        if event=="monitor_touch" then
            if not self.monitorName or a~=self.monitorName then return false end
            if self.monitor then return app:touch(self.monitor,b,c) end
            return false
        elseif event=="mouse_click" then
            if self.terminal then return app:touch(self.terminal,b,c) end
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
