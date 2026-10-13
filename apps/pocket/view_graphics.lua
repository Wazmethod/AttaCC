local gfx = require("lib.display_graphics")

local M = {}

local pw,ph=0,0
local hitboxes={}
local graphicsMode=1

local C={
    bg=colors.black,panel=colors.gray,border=colors.lightGray,
    good=colors.lime,warn=colors.orange,bad=colors.red,
    accent=colors.cyan,blue=colors.blue,yellow=colors.yellow,
    white=colors.white,muted=colors.lightGray,
}

local function fill(x,y,w,h,color) return gfx.fill(term,x,y,w,h,color) end
local function frame(x,y,w,h,color) return gfx.frame(term,x,y,w,h,color) end
local function textWidth(value,scale) return gfx.textWidth(value,scale) end
local function text(x,y,value,color,scale) return gfx.text(term,x,y,value,color,scale) end
local function addHit(x,y,w,h,action,arg) return gfx.addHit(hitboxes,x,y,w,h,action,arg) end
local function button(x,y,w,h,label,color,action,arg)
    return gfx.button(term,hitboxes,x,y,w,h,label,color,action,arg,C,false)
end

local function buildPages(data)
    local pages={{kind="home",id="home",label="HOME"}}
    local groups=data and data.ui and data.ui.groups
    for _,group in ipairs(type(groups)=="table" and groups or {}) do
        if group.id then
            table.insert(pages,{kind="group",id=tostring(group.id),
                label=tostring(group.title or group.id)})
        end
    end
    table.insert(pages,{kind="machines",id="machines",label="MACHINES"})
    table.insert(pages,{kind="events",id="events",label="EVENTS"})
    table.insert(pages,{kind="system",id="system",label="SYSTEM"})
    return pages
end

function M.pageCount(data)
    return #buildPages(data)
end

local function pageDef(page,data)
    local pages=buildPages(data)
    if page<1 then page=1 end
    if page>#pages then page=#pages end
    return pages[page],pages
end

local function findGroup(data,id)
    local groups=data and data.ui and data.ui.groups
    for _,group in ipairs(type(groups)=="table" and groups or {}) do
        if tostring(group.id)==tostring(id) then return group end
    end
end

local function controlsForGroup(data,id)
    local out={}
    local controls=data and data.ui and data.ui.controls
    for _,control in ipairs(type(controls)=="table" and controls or {}) do
        if tostring(control.group or "default")==tostring(id) then table.insert(out,control) end
    end
    return out
end

local function tone(t)
    return t=="bad" and C.bad or t=="warn" and C.warn or t=="good" and C.good or C.blue
end

local function header(page,data,masterAlive,sourceFresh,pending)
    fill(0,0,pw,17,C.panel)
    local app=data and data.ui and data.ui.app
    text(5,5,(app and app.title) or (data and data.ui and data.ui.title) or "ATTACC",C.yellow,1)
    local status=pending and C.warn or (not masterAlive and C.bad or (sourceFresh and C.good or C.warn))
    fill(pw-13,3,9,9,status)
end

local function pager(page,data)
    local def,pages=pageDef(page,data)
    local y=ph-20
    fill(0,y,pw,20,C.panel)
    button(3,y+3,22,14,"<",C.blue,"page",page>1 and page-1 or #pages)
    button(pw-25,y+3,22,14,">",C.blue,"page",page<#pages and page+1 or 1)
    local label=tostring(def.label or "?")
    text(math.max(28,math.floor((pw-textWidth(label,1))/2)),y+7,label,C.white,1)
end

local function home(data,sourceFresh)
    if not data then
        text(8,28,"NO TELEMETRY",C.bad,2)
        return
    end
    local ui=data.ui or {}
    local state=tostring(ui.state or "UNKNOWN")
    fill(5,23,pw-10,19,sourceFresh and C.good or C.bad)
    text(10,29,sourceFresh and state or "DATA STALE",C.white,1)

    local metrics=type(ui.metrics)=="table" and ui.metrics or {}
    local y=49
    for i=1,math.min(#metrics,5) do
        local m=metrics[i]
        local value=tostring(m.value or "-")..(m.unit and (" "..tostring(m.unit)) or "")
        text(8,y,tostring(m.label or "?"),C.accent,1)
        text(math.floor(pw/2),y,value,C.white,1)
        y=y+13
    end
end

local function groupView(data,id)
    local g=findGroup(data,id)
    if not g then text(8,28,"GROUP UNAVAILABLE",C.warn,1) return end
    text(8,24,tostring(g.title or id),C.accent,1)

    local metrics=type(g.metrics)=="table" and g.metrics or {}
    local y=39
    for i=1,math.min(#metrics,4) do
        local m=metrics[i]
        local value=tostring(m.value or "-")..(m.unit and (" "..tostring(m.unit)) or "")
        text(8,y,tostring(m.label or "?"),C.muted,1)
        text(math.floor(pw/2),y,value,C.white,1)
        y=y+12
    end

    local controls=controlsForGroup(data,id)
    local startY=93
    local gap=4
    local bw=math.floor((pw-12-gap)/2)
    for i,control in ipairs(controls) do
        local row=math.floor((i-1)/2)
        local col=(i-1)%2
        local by=startY+row*21
        if by+17>ph-23 then break end
        local bx=4+col*(bw+gap)
        button(bx,by,bw,17,tostring(control.label or control.command),tone(control.tone),"command",control)
    end
end

local function machinesView(apps,selectedKey)
    text(8,24,"CONTROLLABLE MACHINES",C.accent,1)
    if type(apps)~="table" or #apps==0 then
        text(8,40,"NO APPS",C.warn,1)
        return
    end
    local y=39
    for _,app in ipairs(apps) do
        if y+17>ph-23 then break end
        local selected=app.key==selectedKey
        local label=tostring(app.machineLabel or app.machine or app.title or app.key)
        button(5,y,pw-10,17,label,selected and C.accent or (app.fresh and C.blue or C.warn),"app_select",app.key)
        y=y+21
    end
end

local function eventsView(events)
    text(8,24,"EVENTS",C.accent,1)
    local y=40
    for i=1,math.min(#(events or {}),math.floor((ph-65)/12)) do
        local e=events[i]
        local col=e.level=="critical" and C.bad or e.level=="warning" and C.warn
            or e.level=="success" and C.good or C.accent
        text(8,y,tostring(e.code or e.message or "EVENT"),col,1)
        y=y+12
    end
end

local function systemView(nodes,selected,confirming)
    text(8,24,"NETWORK NODES",C.accent,1)
    local y=39
    for _,node in ipairs(nodes or {}) do
        if y+16>ph-45 then break end
        local on=selected and selected[node.key]
        button(5,y,pw-10,16,(on and "[X] " or "[ ] ")..tostring(node.label or node.key),
            on and C.accent or C.blue,"node_toggle",node.key)
        y=y+19
    end
    button(5,ph-42,pw-10,17,confirming and "CONFIRM REBOOT" or "REBOOT SELECTED",
        confirming and C.bad or C.warn,"node_reboot_selected")
end

function M.init(requestedMode)
    if type(term.setGraphicsMode)~="function" or type(term.drawPixels)~="function" then
        error("CC:Graphics unavailable on pocket terminal")
    end
    graphicsMode=requestedMode or 1
    term.setGraphicsMode(graphicsMode)
    local ok,w,h=pcall(term.getSize,graphicsMode)
    if ok and tonumber(w) and tonumber(h) then pw,ph=w,h
    else local tw,th=term.getSize(); pw,ph=tw*6,th*9 end
end

function M.draw(page,data,events,masterAlive,sourceFresh,pending,toast,toastColor,nodes,selected,confirming,apps,selectedAppKey)
    hitboxes={}
    local frozen=type(term.setFrozen)=="function"
    if frozen then pcall(term.setFrozen,true) end
    fill(0,0,pw,ph,C.bg)
    header(page,data,masterAlive,sourceFresh,pending)

    local def=pageDef(page,data)
    if def.kind=="home" then home(data,sourceFresh)
    elseif def.kind=="group" then groupView(data,def.id)
    elseif def.kind=="machines" then machinesView(apps,selectedAppKey)
    elseif def.kind=="events" then eventsView(events)
    elseif def.kind=="system" then systemView(nodes or {},selected or {},confirming)
    end

    if toast then
        fill(4,ph-40,pw-8,14,colors.black)
        frame(4,ph-40,pw-8,14,toastColor or C.white)
        text(8,ph-36,tostring(toast),toastColor or C.white,1)
    end

    pager(page,data)
    if frozen then pcall(term.setFrozen,false) end
end

function M.click(page,data,x,y,nodes,selected,apps,selectedAppKey)
    return gfx.hit(hitboxes,x,y)
end

return M
