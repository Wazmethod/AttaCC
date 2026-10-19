-- Elevator maintenance screen in the SDK's existing CraftOS multishell tab.
-- The CC shell remains separate, and the external-monitor UI is unchanged.
local M={}
function M.setup(app,controller,refresh)
    local pending=nil
    local function now() return os.epoch("utc") end
    local function pendingAction()
        if pending and now()>pending.expires then pending=nil end
        return pending and pending.action or nil
    end
    local function manualStatus()
        local action=pendingAction()
        return action and ("CONFIRM "..action.." (click again)") or "READY"
    end
    local function doStop()
        pending=nil
        local ok,err=app:invoke("stop")
        refresh()
        return ok,err
    end
    app:control("maint_stop",{
        label="STOP NOW",remote=false,monitor=false,run=doStop
    })
    for _,command in ipairs({
        {id="maint_go_top",action="go_top",label="GO TOP x2"},
        {id="maint_go_bottom",action="go_bottom",label="GO BOTTOM x2"}
    }) do
        local action=command.action
        app:control(command.id,{
            label=command.label,remote=false,monitor=false,
            run=function()
                local active=pendingAction()
                if active~=action then
                    pending={action=action,expires=now()+5000}
                    app:log("info","Confirm "..action.." within 5 seconds")
                    return true,"confirmation required"
                end
                pending=nil
                local ok,detail=app:invoke(action)
                refresh()
                if not ok then
                    app:log("warning",action.." rejected: "..tostring(detail))
                end
                return ok,detail
            end
        })
    end
    app:maintenance("elevator",{
        title="AttaCC Elevator",
        status={
            {id="floor",label="Current floor",read=function() return controller.snapshot().position end},
            {id="phase",label="Motion",read=function() return controller.snapshot().phase end},
            {id="destination",label="Destination",read=function() return controller.snapshot().destination end},
            {id="sensors",label="Contacts",read=function()
                local state=controller.snapshot()
                return "TOP="..(state.top and "ON" or "OFF")..
                    " BOTTOM="..(state.bottom and "ON" or "OFF")
            end},
            {id="calls",label="Floor calls",read=function()
                local state=controller.snapshot()
                return "TOP="..(state.callTop and "ON" or "OFF")..
                    " BOTTOM="..(state.callBottom and "ON" or "OFF")..
                    " CABIN="..(state.callCabin and "ON" or "OFF")
            end},
            {id="manual",label="Local command",read=manualStatus},
            {id="poll",label="Controller updates",read=function()
                local state=controller.snapshot()
                return tostring(state.updates or 0)..
                    " (last "..tostring(state.lastUpdateAgeMs or -1).." ms ago)"
            end},
            {id="host",label="SDK loop",read=function()
                local loop=app.hostLoop
                if not loop then return "NOT STARTED" end
                return tostring(loop.ticks).." ticks / "..tostring(loop.phase)..
                    " / age "..tostring(loop.lastCompletedAt>0
                        and math.max(0,os.epoch("utc")-loop.lastCompletedAt) or -1).." ms"
            end},
            {id="settle",label="Preparing timer",read=function()
                local state=controller.snapshot()
                if state.phase~="PREPARING" then return "-" end
                return tostring(state.preparingElapsedMs or -1).." ms elapsed; "..
                    tostring(state.preparingRemainingMs or -1).." ms remaining"..
                    " (set "..tostring(state.preparingDelayMs or -1).." ms)"
            end},
            {id="error",label="Last error",read=function() return controller.snapshot().error end}
        },
        tools={"maint_stop","maint_go_top","maint_go_bottom"},
        logLimit=4
    })
end
return M
