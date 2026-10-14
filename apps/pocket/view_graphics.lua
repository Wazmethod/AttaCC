local gfx = require("lib.display_graphics")
local dashboard = require("lib.dashboard")
local pocketPages = require("lib.pocket_pages")

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

local GRAPH_COLORS={
    cyan=colors.cyan,orange=colors.orange,lime=colors.lime,blue=colors.blue,
    red=colors.red,yellow=colors.yellow,white=colors.white,
    lightBlue=colors.lightBlue,magenta=colors.magenta,
}

local function fill(x,y,w,h,color) return gfx.fill(term,x,y,w,h,color) end
local function frame(x,y,w,h,color) return gfx.frame(term,x,y,w,h,color) end
local function textWidth(value,scale) return gfx.textWidth(value,scale) end
local function text(x,y,value,color,scale) return gfx.text(term,x,y,value,color,scale) end
local function button(x,y,w,h,label,color,action,arg,active)
    return gfx.button(term,hitboxes,x,y,w,h,label,color,action,arg,C,active)
end

local function buildPages(data)
    return pocketPages.build(data)
end

function M.pageCount(data)
    return math.max(1,#buildPages(data))
end

local function pageDef(page,data)
    local pages=buildPages(data)
    if #pages==0 then return nil,pages end
    page=math.max(1,math.min(tonumber(page) or 1,#pages))
    return pages[page],pages
end

local function tone(t)
    return t=="bad" and C.bad or t=="warn" and C.warn or t=="good" and C.good or C.blue
end

local function header(page,data,masterAlive,sourceFresh,pending)
    fill(0,0,pw,17,C.panel)
    local app=data and data.ui and data.ui.app
    text(5,5,(app and app.title) or "ATTACC POCKET",C.yellow,1)
    local status=pending and C.warn or (not masterAlive and C.bad or (sourceFresh and C.good or C.warn))
    fill(pw-13,3,9,9,status)
end

local function pager(page,data)
    local def,pages=pageDef(page,data)
    local y=ph-20
    fill(0,y,pw,20,C.panel)
    button(3,y+3,22,14,"<",C.blue,"page",page>1 and page-1 or #pages)
    button(pw-25,y+3,22,14,">",C.blue,"page",page<#pages and page+1 or 1)
    local label=dashboard.pageLabel(def)
    text(math.max(28,math.floor((pw-textWidth(label,1))/2)),y+7,label,C.white,1)
end

local function home(data,sourceFresh,masterAlive,apps)
    text(8,26,"ATTACC POCKET",C.accent,2)
    text(8,48,"MASTER",C.muted,1)
    text(math.floor(pw/2),48,masterAlive and "ONLINE" or "OFFLINE",masterAlive and C.good or C.bad,1)
    text(8,62,"MACHINES",C.muted,1)
    text(math.floor(pw/2),62,tostring(#(apps or {})),C.white,1)

    if data then
        local ui=data.ui or {}
        text(8,78,"SELECTED",C.muted,1)
        text(math.floor(pw/2),78,gfx.fitText(
            tostring(ui.app and (ui.app.machineLabel or ui.app.title) or "?"),
            math.floor(pw/2)-12,1),sourceFresh and C.good or C.warn,1)
        text(8,92,"STATE",C.muted,1)
        text(math.floor(pw/2),92,tostring(ui.state or "UNKNOWN"),C.white,1)
    else
        text(8,78,"NO MACHINE DATA",C.warn,1)
    end
end

local function machinesView(apps,selectedKey)
    text(8,24,"SELECT MACHINE",C.accent,1)
    if type(apps)~="table" or #apps==0 then
        text(8,40,"NO CONTROLLABLE APPS",C.warn,1)
        return
    end
    local y=39
    for _,app in ipairs(apps) do
        if y+17>ph-23 then break end
        local selected=app.key==selectedKey
        local label=tostring(app.machineLabel or app.machine or app.title or app.key)
        button(5,y,pw-10,17,label,selected and C.accent or (app.fresh and C.blue or C.warn),
            "app_select",app.key,selected)
        y=y+21
    end
end

local function dataView(def)
    text(8,24,dashboard.pageLabel(def),C.accent,1)
    local y=42
    for _,m in ipairs(def.items or {}) do
        if y+11>ph-23 then break end
        local value=tostring(m.value or "-")..(m.unit and (" "..tostring(m.unit)) or "")
        text(8,y,tostring(m.label or "?"),C.muted,1)
        text(math.floor(pw/2),y,gfx.fitText(value,math.floor(pw/2)-10,1),C.white,1)
        y=y+13
    end
end

local function graphView(def,history)
    local graphs=def.items or {}
    text(8,22,dashboard.pageLabel(def),C.accent,1)
    if #graphs==0 then text(8,40,"NO GRAPH DATA",C.warn,1) return end

    local top=35
    local bottom=ph-24
    local gap=5
    local each=math.floor((bottom-top-gap*math.max(0,#graphs-1))/#graphs)

    for index,meta in ipairs(graphs) do
        local y=top+(index-1)*(each+gap)
        frame(5,y,pw-10,each,C.border)
        local value=tonumber(meta.value) or 0
        local lo=tonumber(meta.min)
        local hi=tonumber(meta.max)
        local margin=tonumber(meta.margin) or 0
        if lo==nil then lo=value-margin end
        if hi==nil then hi=value+math.max(1,margin) end
        if hi<=lo then hi=lo+1 end
        local col=GRAPH_COLORS[tostring(meta.color)] or C.accent

        text(9,y+5,tostring(meta.label or meta.id or "GRAPH"),C.white,1)
        text(pw-72,y+5,string.format("%.1f %s",value,tostring(meta.unit or "")),col,1)

        local bx,by,bw,bh=10,y+18,pw-20,math.max(8,each-26)
        fill(bx,by,bw,bh,colors.black)
        local gx=math.max(1,tonumber(meta.gridX) or 6)
        local gy=math.max(1,tonumber(meta.gridY) or 4)
        for i=0,gx do
            local xx=bx+math.floor((bw-1)*i/gx)
            gfx.line(term,xx,by,xx,by+bh-1,colors.gray)
        end
        for i=0,gy do
            local yy=by+math.floor((bh-1)*i/gy)
            gfx.line(term,bx,yy,bx+bw-1,yy,colors.gray)
        end

        local samples=history and history[tostring(meta.id or meta.label or index)] or {}
        if #samples>=2 then
            local px,py=nil,nil
            for i,sample in ipairs(samples) do
                local v=tonumber(sample.value) or lo
                if v<lo then lo=v-margin end
                if v>hi then hi=v+margin end
                local ratio=math.max(0,math.min(1,(v-lo)/(hi-lo)))
                local xx=bx+math.floor((bw-1)*(i-1)/math.max(1,#samples-1))
                local yy=by+bh-1-math.floor(ratio*(bh-1))
                if px then gfx.line(term,px,py,xx,yy,col) end
                px,py=xx,yy
            end
        end
        text(bx+2,by+2,string.format("%.0f",hi),C.muted,1)
        text(bx+2,by+bh-7,string.format("%.0f",lo),C.muted,1)
    end
end

local function controlsView(def)
    text(8,24,dashboard.pageLabel(def),C.accent,1)
    local controls=def.items or {}
    local gap=4
    local bw=math.floor((pw-12-gap)/2)
    local startY=42
    for i,control in ipairs(controls) do
        local row=math.floor((i-1)/2)
        local col=(i-1)%2
        local by=startY+row*21
        if by+17>ph-23 then break end
        local bx=4+col*(bw+gap)
        button(bx,by,bw,17,tostring(control.label or control.command),tone(control.tone),"command",control)
    end
end

local function eventsView(events)
    text(8,24,"EVENTS",C.accent,1)
    local y=40
    for i=1,math.min(#(events or {}),math.floor((ph-65)/15)) do
        local e=events[i]
        local col=e.level=="critical" and C.bad or e.level=="warning" and C.warn
            or e.level=="success" and C.good or C.accent
        local host=tostring(e.hostname or e.machine or "?")
        button(5,y,pw-10,13,gfx.fitText(host.." | "..tostring(e.code or "EVENT"),pw-18,1),
            col,"event_machine",e.machine)
        y=y+16
    end
end

local function systemView(nodes,selected,confirming,masterAlive)
    text(8,24,"POCKET SYSTEM",C.accent,1)
    text(8,42,"COMPUTER ID",C.muted,1)
    text(math.floor(pw/2),42,tostring(os.getComputerID()),C.white,1)
    text(8,56,"MASTER",C.muted,1)
    text(math.floor(pw/2),56,masterAlive and "ONLINE" or "OFFLINE",masterAlive and C.good or C.bad,1)
    text(8,70,"NODES",C.muted,1)
    text(math.floor(pw/2),70,tostring(#(nodes or {})),C.white,1)

    button(5,ph-42,pw-10,17,confirming and "CONFIRM REBOOT" or "REBOOT SELECTED",
        confirming and C.bad or C.warn,"node_reboot_selected")
end

function M.init(requestedMode)
    if type(term.setGraphicsMode)~="function" or type(term.drawPixels)~="function" then
        error("CC:Graphics unavailable")
    end
    graphicsMode=requestedMode or 1
    term.setGraphicsMode(graphicsMode)
    local ok,w,h=pcall(term.getSize,graphicsMode)
    if ok and tonumber(w) and tonumber(h) then pw,ph=w,h
    else local tw,th=term.getSize(); pw,ph=tw*6,th*9 end
end

function M.draw(page,data,events,masterAlive,sourceFresh,pending,toast,toastColor,nodes,selected,confirming,apps,selectedAppKey,history)
    hitboxes={}
    local frozen=type(term.setFrozen)=="function"
    if frozen then pcall(term.setFrozen,true) end
    fill(0,0,pw,ph,C.bg)
    header(page,data,masterAlive,sourceFresh,pending)

    local def=pageDef(page,data)
    if def.subTotal and def.subTotal > 1 then
        button(5,22,24,14,"<",C.blue,"subpage",{kind=def.kind,delta=-1})
        button(pw-29,22,24,14,">",C.blue,"subpage",{kind=def.kind,delta=1})
        text(math.floor(pw/2)-16,26,tostring(def.subIndex).."/"..tostring(def.subTotal),C.muted,1)
    end
    if def.kind=="home" then home(data,sourceFresh,masterAlive,apps)
    elseif def.kind=="machines" then machinesView(apps,selectedAppKey)
    elseif def.kind=="data" then dataView(def)
    elseif def.kind=="graphs" then graphView(def,history)
    elseif def.kind=="controls" then controlsView(def)
    elseif def.kind=="events" then eventsView(events)
    elseif def.kind=="system" then systemView(nodes or {},selected or {},confirming,masterAlive)
    end

    if toast then
        fill(4,ph-40,pw-8,14,colors.black)
        frame(4,ph-40,pw-8,14,toastColor or C.white)
        text(8,ph-36,tostring(toast),toastColor or C.white,1)
    end

    pager(page,data)
    if frozen then pcall(term.setFrozen,false) end
end

function M.click(page,data,x,y)
    return gfx.hit(hitboxes,x,y)
end

function M.actionAt(x,y)
    return gfx.hit(hitboxes,x,y)
end

return M
