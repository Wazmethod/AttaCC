-- Native CraftOS maintenance screen. No custom terminal UI.
local M={}
function M.setup(app,controller,refresh)
    local pending=nil
    local untilAt=0
    local now=function() return os.epoch("utc") end

    app:control("maint_stop",{
        label="STOP NOW",remote=false,monitor=false,
        run=function()
            pending=nil
            local ok,err=app:invoke("stop")
            refresh()
            return ok,err
        end
    })
    for _,cmd in ipairs({
        {id="maint_go_top",action="go_top",label="GO TOP x2"},
        {id="maint_go_bottom",action="go_bottom",label="GO BOTTOM x2"}
    }) do
        local action=cmd.action
        app:control(cmd.id,{
            label=cmd.label,remote=false,monitor=false,
            run=function()
                if pending~=action or now()>untilAt then
                    pending=action
                    untilAt=now()+5000
                    return true,"click again to confirm"
                end
                pending=nil
                local ok,err=app:invoke(action)
                refresh()
                return ok,err
            end
        })
    end

    local status={
        {id="mode",label="Mode",read=function()
            return app:config("motion.readOnly",false) and "READ-ONLY" or "LIVE"
        end},
        {id="floor",label="Current floor",read=function()
            return controller.snapshot().position
        end},
        {id="phase",label="Motion",read=function()
            return controller.snapshot().phase
        end},
        {id="destination",label="Destination",read=function()
            return controller.snapshot().destination
        end},
        {id="contacts",label="Contacts",read=function()
            local s=controller.snapshot()
            return "TOP="..(s.top and "ON" or "OFF")..
                " BOTTOM="..(s.bottom and "ON" or "OFF")
        end},
        {id="calls",label="Floor calls",read=function()
            local s=controller.snapshot()
            return "TOP="..(s.callTop and "ON" or "OFF")..
                " BOTTOM="..(s.callBottom and "ON" or "OFF")..
                " CABIN="..(s.callCabin and "ON" or "OFF")
        end},
        {id="error",label="Last error",read=function()
            return controller.snapshot().error
        end},
    }
    if app:config("debug",false)==true then
        status[#status+1]={id="polls",label="Polling",read=function()
            local s=controller.snapshot()
            return tostring(s.polls).." polls; last "..tostring(s.lastPollAgeMs).." ms ago"
        end}
    end
    app:maintenance("elevator",{
        title="AttaCC Elevator",
        status=status,
        tools={"maint_stop","maint_go_top","maint_go_bottom"},
        logLimit=4
    })
end
return M
