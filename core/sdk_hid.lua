-- HID dispatch for SDK application hosts.
-- Rendering ownership remains with app:draw and app:touch.
local M={}
function M.new(app,options)
    options=options or {}
    local self={last=nil}
    function self:setRender(result)
        self.last=result
    end
    function self:handle(event,a,b,c)
        if event=="monitor_touch" then
            if options.monitorName and a~=options.monitorName then return false end
            if self.last then return app:touch(self.last,b,c) end
            return false
        elseif event=="mouse_click" then
            if self.last then return app:touch(self.last,b,c) end
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
