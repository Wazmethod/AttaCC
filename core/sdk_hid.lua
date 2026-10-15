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
            -- On some angled 3-panel monitors the panel permutation used
            -- for content buttons maps visible pager arrows onto tabs.
            -- Pager hitboxes are pure navigation: resolve only these two
            -- from raw screen coordinates before panel-specific remapping.
            -- Never apply this shortcut to hardware controls or view tabs.
            if options.monitorTouchProfile=="angled3_swap" then
                local rawAction=hit(result,b,c)
                if rawAction=="display.previous" or rawAction=="display.next" then
                    return app:touch(result,b,c)
                end
            end
            -- The current CC:Graphics monitor reports pixel positions directly.
            -- Do not rescale into text cells or try two conflicting hitboxes.
            local x,y=b,c
            -- Preserve the proven legacy collector angled3 mapping:
            -- the outer thirds are mirrored locally, the centre is untouched.
            local profile=options.monitorTouchProfile or "normal"
            if profile=="angled3" and type(result.width)=="number" then
                local third=result.width/3
                if x<third then
                    x=(third-1)-x
                elseif x>=third*2 then
                    local localX=x-third*2
                    local wingW=result.width-third*2
                    x=third*2+(wingW-1-localX)
                end
                x=math.floor(x+0.5)
            elseif profile=="angled3_swap" and type(result.width)=="number" then
                local third=result.width/3
                if x<third then
                    x=x+2*third
                elseif x>=2*third then
                    x=x-2*third
                end
                x=math.floor(x+0.5)
            elseif profile=="mirror_x" and type(result.width)=="number" then
                x=result.width-1-x
            end
            if options.monitorTouchFlipX==true then
                x=result.width-1-x
            end
            if options.monitorTouchFlipY==true then
                y=result.height-1-y
            end
            -- Insets compensate a monitor whose touch surface extends under
            -- the physical bezel. Apply after panel permutation/mirroring.
            local insetX=math.max(0,math.min((result.width-1)/3,
                tonumber(options.monitorTouchInsetX) or 0))
            local insetY=math.max(0,math.min((result.height-1)/3,
                tonumber(options.monitorTouchInsetY) or 0))
            if profile=="angled3_swap" and insetX>0 then
                -- Outer panels need correction toward their own OUTER edges.
                -- The old whole-screen compression moved outer touch points
                -- away from the joins and created dead zones beside the centre.
                local third=result.width/3
                if x<third then
                    x=x-insetX
                elseif x>=third*2 then
                    x=x+insetX
                end
            elseif insetX>0 then
                x=insetX+x*(result.width-2*insetX)/result.width
            end
            x=math.floor(math.max(0,math.min(result.width-1,x))+0.5)
            y=math.floor(insetY+y*(result.height-2*insetY)/result.height+0.5)
            if not hit(result,x,y) then return false,"touch misses graphics hitboxes" end
            return app:touch(result,x,y)
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
