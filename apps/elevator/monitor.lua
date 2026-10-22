-- Fixed 1x1 CC:Graphics screen for Elevator.
-- The SDK host still handles display scheduling, touch, I/O and network.
local gfx=require("lib.display_graphics")
local M={}
local C={
    bg=colors.black, panel=colors.gray, edge=colors.lightGray,
    text=colors.white, accent=colors.cyan, active=colors.lime,
    warn=colors.orange, disabled=colors.gray,
}
local lastName,lastKey,lastResult

local function centerText(target,label,x,y,width,color,scale)
    scale=scale or 1
    label=gfx.fitText(label,math.max(0,width-2),scale)
    local length=gfx.textWidth(label,scale)
    gfx.text(target,x+math.floor((width-length)/2),y,label,color,scale)
end

local function drawButton(target,hits,x,y,w,h,label,enabled,action)
    if enabled then
        gfx.button(target,hits,x,y,w,h,label,C.panel,action,nil,{
            border=C.edge,white=C.text,accent=C.accent
        })
    else
        gfx.fill(target,x,y,w,h,C.bg)
        gfx.frame(target,x,y,w,h,C.disabled)
        centerText(target,label,x,y+math.floor((h-5)/2),w,C.disabled)
    end
end

function M.render(monitor,state,readOnly)
    if not monitor or type(monitor.setGraphicsMode)~="function" then
        return {ok=false,warning="CC:Graphics required"}
    end
    -- sdk_host wraps the peripheral every redraw; use its stable name,
    -- not wrapper-table identity, to avoid resetting graphics each tick.
    local name=peripheral.getName(monitor)
    if name~=lastName then
        lastName=name
        lastKey=nil
        local ready,err=pcall(monitor.setGraphicsMode,1)
        if not ready then return {ok=false,warning=tostring(err)} end
    end
    local sized,w,h=pcall(monitor.getSize,1)
    if not sized or type(w)~="number" or type(h)~="number" then
        return {ok=false,warning="unknown graphics size"}
    end
    -- The standard SDK card renderer rejects this small 1x1 screen.
    -- This layout needs only room for a floor number and two touch buttons.
    if w<36 or h<34 then
        return {ok=false,warning="monitor too small"}
    end
    local phase=state.phase or "IDLE"
    local position=state.position or "UNKNOWN"
    local floor=position=="TOP" and "2" or position=="BOTTOM" and "1" or "-"
    local moving=phase=="MOVING"
    local idle=phase=="IDLE"
    local key=table.concat({tostring(w),tostring(h),phase,position,
        tostring(state.destination),tostring(readOnly)},":")
    if key==lastKey and lastResult then return lastResult end

    gfx.fill(monitor,0,0,w,h,C.bg)
    local margin=math.max(2,math.min(4,math.floor(math.min(w,h)/15)))
    local buttonX=math.floor(w*0.52)
    local buttonW=w-buttonX-margin
    local gap=math.max(3,math.floor(h*0.06))
    local buttonH=math.floor((h-2*margin-gap)/2)
    local infoX=margin
    local infoW=buttonX-margin*2
    local hits={}

    gfx.frame(monitor,infoX,margin,infoW,h-2*margin,C.edge)
    centerText(monitor,"FLOOR",infoX,margin+5,infoW,C.accent)
    local floorScale=math.max(1,math.min(4,math.floor((infoW-6)/4),
        math.floor((h-31)/5)))
    local floorY=margin+math.floor((h-2*margin-5*floorScale)/2)
    centerText(monitor,floor,infoX,floorY,infoW,C.text,floorScale)
    local footer=phase=="ERROR" and "ERROR"
        or moving and ("TO "..(state.destination=="TOP" and "2" or "1"))
        or readOnly and "LOCKED" or "IDLE"
    centerText(monitor,footer,infoX,h-margin-10,infoW,
        phase=="ERROR" and C.warn or moving and C.active or C.edge)

    -- All motor requests go through the existing SDK control IDs.
    -- Never write to the Bridge from a monitor_touch callback.
    local canMove=idle and not readOnly and floor~="-"
    drawButton(monitor,hits,buttonX,margin,buttonW,buttonH,
        "UP",canMove and position~="TOP","display.control.go_top")
    drawButton(monitor,hits,buttonX,margin+buttonH+gap,buttonW,buttonH,
        "DOWN",canMove and position~="BOTTOM","display.control.go_bottom")

    local boxes={}
    for _,hit in ipairs(hits) do
        boxes[#boxes+1]={x1=hit.x1,y1=hit.y1,x2=hit.x2,y2=hit.y2,
            id=hit.action}
    end
    local result={ok=true,backend="ccgraphics",view="elevator_monitor",
        width=w,height=h,page=1,pageCount=1,hitboxes=boxes}
    lastKey,lastResult=key,result
    return result
end

return M
