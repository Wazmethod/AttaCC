local gfx = require("lib.display_graphics")
local dashboard = require("lib.dashboard")
local uiPages = require("lib.ui_pages")

local M = {}
local hitboxes={}
local mode=1
local pw,ph=0,0

local C={
    bg=colors.black,panel=colors.gray,panelDark=colors.black,border=colors.lightGray,
    good=colors.lime,warn=colors.orange,bad=colors.red,accent=colors.cyan,
    blue=colors.blue,yellow=colors.yellow,white=colors.white,muted=colors.lightGray,
}

local function fill(...) return gfx.fill(...) end
local function frame(...) return gfx.frame(...) end
local function text(...) return gfx.text(...) end
local function textWidth(...) return gfx.textWidth(...) end
local function panel(mon,x,y,w,h,title) return gfx.panel(mon,x,y,w,h,title,C) end
local function button(mon,x,y,w,h,label,color,action,arg,active)
    return gfx.button(mon,hitboxes,x,y,w,h,label,color,action,arg,C,active)
end

local NAV={{"home","HOME"},{"machine","MACHINE"},{"events","EVENTS"},{"network","NETWORK"}}

local function selectedApp(state)
    for _,app in ipairs(state.apps or {}) do
        if app.key==state.selectedAppKey then return app end
    end
    return (state.apps or {})[1]
end

local function tone(t)
    return t=="bad" and C.bad or t=="warn" and C.warn or t=="good" and C.good or C.blue
end

local function drawHeader(mon,title)
    fill(mon,0,0,pw,18,C.panel)
    text(mon,6,6,"ATTACC MASTER",C.accent,1)
    local tw=textWidth(title,1)
    text(mon,math.max(110,math.floor((pw-tw)/2)),6,title,C.yellow,1)
end

local function drawNav(mon,state)
    local y=ph-20
    fill(mon,0,y,pw,20,C.panel)
    local gap=3
    local bw=math.floor((pw-gap*(#NAV+1))/#NAV)
    for i,item in ipairs(NAV) do
        local x=gap+(i-1)*(bw+gap)
        button(mon,x,y+3,bw,14,item[2],C.blue,"page",item[1],state.page==item[1])
    end
end

local function drawHome(mon,state)
    drawHeader(mon,"HOME")
    local y=24
    local gap=6
    local half=math.floor((pw-gap*3)/2)
    local h=math.max(48,math.floor((ph-y-28-gap)/2))
    local home=state.home or {}

    if home.machines~=false then
        panel(mon,gap,y,half,h,"MACHINES")
        local yy=y+20
        for i=1,math.min(#(state.apps or {}),math.floor((h-24)/11)) do
            local app=state.apps[i]
            text(mon,gap+7,yy,tostring(app.machineLabel or app.machine or app.title),
                app.fresh and C.good or C.warn,1)
            yy=yy+11
        end
        if #(state.apps or {})==0 then text(mon,gap+7,yy,"NO CONTROLLABLE MACHINES",C.warn,1) end
    end

    if home.network~=false then
        panel(mon,gap*2+half,y,half,h,"NETWORK")
        text(mon,gap*2+half+8,y+25,tostring(#(state.nodes or {})).." NODES",C.white,2)
    end

    local by=y+h+gap
    local bh=ph-by-25
    if home.events~=false then
        panel(mon,gap,by,half,bh,"RECENT EVENTS")
        local yy=by+20
        for i=1,math.min(3,#(state.events or {})) do
            local e=state.events[i]
            text(mon,gap+7,yy,gfx.fitText(
                tostring(e.hostname or e.machine or "?").." "..tostring(e.code or "EVENT"),
                half-14,1),
                e.level=="critical" and C.bad or e.level=="warning" and C.warn or C.muted,1)
            yy=yy+11
        end
    end

    panel(mon,gap*2+half,by,half,bh,"SYSTEM")
    local x=gap*2+half+8
    local yy=by+20
    if home.storage~=false then
        local s=state.storage or {}
        text(mon,x,yy,"STORAGE "..(s.available and string.upper(tostring(s.backend or "?")) or "INACTIVE"),
            s.available and C.good or C.warn,1)
        yy=yy+12
    end
    if home.web~=false then
        local web=state.web or {}
        text(mon,x,yy,"WEB "..string.upper(tostring(web.status or "?")),
            web.status=="active" and C.good or C.warn,1)
        yy=yy+12
    end
    local d=state.display or {}
    text(mon,x,yy,"DISPLAY "..string.upper(tostring(d.state or "?")),
        d.state=="active" and C.good or C.warn,1)
end

local function drawMachineSelector(mon,state,y)
    local apps=state.apps or {}
    if #apps==0 then
        text(mon,8,y+5,"NO CONTROLLABLE MACHINE",C.warn,1)
        return y+22
    end
    local count=math.min(#apps,4)
    local gap=4
    local bw=math.floor((pw-gap*(count+1))/count)
    for i=1,count do
        local app=apps[i]
        local x=gap+(i-1)*(bw+gap)
        local label=gfx.fitText(tostring(app.machineLabel or app.machine or app.title),bw-8,1)
        button(mon,x,y,bw,16,label,app.fresh and C.blue or C.warn,
            "machine_select",app.key,app.key==state.selectedAppKey)
    end
    return y+21
end

local function flattenGroups(app)
    local ui=app and app.data and app.data.ui
    return ui and type(ui.groups)=="table" and ui.groups or {}
end

local function pageNav(mon,x,y,w,h,page,count,label)
    if count<=1 then
        text(mon,x+8,y+h-12,label or "",C.muted,1)
        return
    end
    local caption=(label or "").." "..tostring(page).."/"..tostring(count)
    text(mon,x+math.max(30,math.floor((w-textWidth(caption,1))/2)),y+h-12,caption,C.muted,1)
    button(mon,x+4,y+h-18,22,14,"<",C.blue,"machine_page",page>1 and page-1 or count,false)
    button(mon,x+w-26,y+h-18,22,14,">",C.blue,"machine_page",page<count and page+1 or 1,false)
end

local function drawData(mon,app,x,y,w,h,page)
    local pages=dashboard.pagesForKind(app.data,"data",{dataPerPage=8})
    if #pages==0 then
        text(mon,x+8,y+20,"NO EXPORTED DATA",C.warn,1)
        return
    end
    page=math.max(1,math.min(tonumber(page) or 1,#pages))
    local def=pages[page]

    panel(mon,x,y,w,h,tostring(def.categoryTitle or "DATA"))
    local yy=y+22
    local cols=2
    local colW=math.floor((w-18)/cols)
    for i,m in ipairs(def.items or {}) do
        local col=(i-1)%cols
        local row=math.floor((i-1)/cols)
        local bx=x+8+col*(colW+4)
        local by=yy+row*18
        if by>y+h-30 then break end
        text(mon,bx,by,gfx.fitText(tostring(m.label or "?"),math.floor(colW*.48),1),C.muted,1)
        local value=tostring(m.value or "-")..(m.unit and (" "..tostring(m.unit)) or "")
        text(mon,bx+math.floor(colW*.5),by,gfx.fitText(value,math.floor(colW*.48),1),C.white,1)
    end
    pageNav(mon,x,y,w,h,page,#pages,dashboard.pageLabel(def))
end

local GRAPH_COLORS = {
    cyan = colors.cyan,
    orange = colors.orange,
    lime = colors.lime,
    blue = colors.blue,
    red = colors.red,
    yellow = colors.yellow,
    white = colors.white,
    lightBlue = colors.lightBlue,
    magenta = colors.magenta,
}

local function graphMeta(app,id)
    local graphs=app.data and app.data.ui and app.data.ui.graphs or {}
    for _,meta in ipairs(type(graphs)=="table" and graphs or {}) do
        if tostring(meta.id)==tostring(id) then return meta end
    end
    return {}
end

local function drawGraph(mon,x,y,w,h,title,samples,meta)
    panel(mon,x,y,w,h,title)
    local gx=x+7; local gy=y+20; local gw=w-14; local gh=h-27
    fill(mon,gx,gy,gw,gh,colors.black)

    meta=meta or {}
    local gridX=math.max(1,tonumber(meta.gridX) or 6)
    local gridY=math.max(1,tonumber(meta.gridY) or 4)

    for i=0,gridX do
        local xx=gx+math.floor((gw-1)*i/gridX)
        gfx.line(mon,xx,gy,xx,gy+gh-1,colors.gray)
    end
    for i=0,gridY do
        local yy=gy+math.floor((gh-1)*i/gridY)
        gfx.line(mon,gx,yy,gx+gw-1,yy,colors.gray)
    end

    if not samples or #samples<2 then
        text(mon,gx+5,gy+math.floor(gh/2),"WAITING FOR HISTORY",C.muted,1)
        return
    end

    local sampleLo,sampleHi=nil,nil
    for _,s in ipairs(samples) do
        local v=tonumber(s.value)
        if v then
            sampleLo=sampleLo and math.min(sampleLo,v) or v
            sampleHi=sampleHi and math.max(sampleHi,v) or v
        end
    end
    if not sampleLo then return end

    local margin=tonumber(meta.margin) or 0
    local lo=tonumber(meta.min)
    local hi=tonumber(meta.max)

    if lo==nil then lo=sampleLo-margin end
    if hi==nil then hi=sampleHi+margin end
    if sampleLo<lo then lo=sampleLo-margin end
    if sampleHi>hi then hi=sampleHi+margin end
    if hi<=lo then hi=lo+1 end

    local curve=GRAPH_COLORS[tostring(meta.color)] or C.accent
    local px,py=nil,nil
    for i,s in ipairs(samples) do
        local v=tonumber(s.value) or lo
        local nx=(i-1)/math.max(1,#samples-1)
        local nv=math.max(0,math.min(1,(v-lo)/(hi-lo)))
        local cx=gx+math.floor(nx*(gw-1))
        local cy=gy+gh-1-math.floor(nv*(gh-1))
        if px then gfx.line(mon,px,py,cx,cy,curve) end
        px,py=cx,cy
    end

    local last=samples[#samples]
    text(mon,gx+4,gy+3,string.format("%.1f",tonumber(last.value) or 0)
        ..(last.unit and (" "..tostring(last.unit)) or ""),curve,1)
    text(mon,gx+4,gy+gh-7,string.format("%.0f",lo),C.muted,1)
    local maxLabel=string.format("%.0f",hi)
    text(mon,gx+gw-gfx.textWidth(maxLabel,1)-3,gy+3,maxLabel,C.muted,1)
end

local function drawGraphs(mon,app,x,y,w,h,page)
    local pages=dashboard.pagesForKind(app.data,"graphs",{graphsPerPage=4})
    if #pages==0 then
        text(mon,x+8,y+20,"NO EXPORTED GRAPHS",C.warn,1)
        return
    end

    page=math.max(1,math.min(tonumber(page) or 1,#pages))
    local def=pages[page]
    local graphs=def.items or {}
    local gap=5
    local halfW=math.floor((w-gap)/2)
    local halfH=math.floor((h-20-gap)/2)

    for i,meta in ipairs(graphs) do
        local col=(i-1)%2
        local row=math.floor((i-1)/2)
        local id=tostring(meta.id or meta.label or i)
        local samples=app.history and app.history[id] or {}
        drawGraph(mon,x+col*(halfW+gap),y+row*(halfH+gap),halfW,halfH,
            tostring(meta.label or id),samples,meta)
    end

    pageNav(mon,x,y,w,h,page,#pages,dashboard.pageLabel(def))
end

local function drawControls(mon,app,x,y,w,h,page)
    local pages=dashboard.pagesForKind(app.data,"controls",{controlsPerPage=8})
    if #pages==0 then
        text(mon,x+8,y+20,"NO CONTROLS EXPORTED",C.muted,1)
        return
    end

    page=math.max(1,math.min(tonumber(page) or 1,#pages))
    local def=pages[page]
    local controls=def.items or {}
    local gap=5
    local bw=math.floor((w-gap)/2)
    local bh=17
    local top=y+18

    text(mon,x+8,y+4,tostring(def.categoryTitle or "CONTROLS"),C.accent,1)

    for i,control in ipairs(controls) do
        local row=math.floor((i-1)/2)
        local col=(i-1)%2
        local by=top+row*(bh+5)
        if by+bh>y+h-20 then break end
        button(mon,x+col*(bw+gap),by,bw,bh,tostring(control.label or control.command),
            tone(control.tone),"command",control,false)
    end

    pageNav(mon,x,y,w,h,page,#pages,dashboard.pageLabel(def))
end

local function drawMachine(mon,state)
    drawHeader(mon,"MACHINE")
    local y=drawMachineSelector(mon,state,22)
    local app=selectedApp(state)
    if not app then return end

    local tabs={{"data","DATA"},{"graphs","GRAPHS"},{"controls","CONTROLS"}}
    local gap=4
    local bw=math.floor((pw-gap*4)/3)
    for i,tab in ipairs(tabs) do
        local x=gap+(i-1)*(bw+gap)
        button(mon,x,y,bw,15,tab[2],C.blue,"machine_tab",tab[1],state.machineTab==tab[1])
    end
    y=y+20

    local contentX=6
    local contentW=pw-12
    local contentH=ph-y-27
    if state.machineTab=="graphs" then drawGraphs(mon,app,contentX,y,contentW,contentH,state.machinePage)
    elseif state.machineTab=="controls" then drawControls(mon,app,contentX,y,contentW,contentH,state.machinePage)
    else drawData(mon,app,contentX,y,contentW,contentH,state.machinePage) end

    if state.pending then
        text(mon,8,ph-29,"WAIT ACK "..tostring(state.pending.command),C.warn,1)
    end
end

local function drawEvents(mon,state)
    drawHeader(mon,"EVENTS")
    local y=24
    local rowH=14
    for i=1,math.min(#(state.events or {}),math.floor((ph-y-25)/rowH)) do
        local e=state.events[i]
        local col=e.level=="critical" and C.bad or e.level=="warning" and C.warn
            or e.level=="success" and C.good or C.accent
        local host=tostring(e.hostname or e.machine or "?")
        text(mon,8,y,gfx.fitText(host,100,1),C.white,1)
        text(mon,112,y,gfx.fitText(tostring(e.code or "EVENT"),100,1),col,1)
        text(mon,220,y,gfx.fitText(tostring(e.message or ""),pw-228,1),C.muted,1)
        if e.machine then gfx.addHit(hitboxes,6,y-3,pw-12,rowH,"event_machine",e.machine) end
        y=y+rowH
    end
    if y==24 then text(mon,8,y,"NO EVENTS",C.muted,1) end
end

local function drawNetwork(mon,state)
    drawHeader(mon,"NETWORK")
    local y=24
    for _,node in ipairs(state.nodes or {}) do
        if y+18>ph-24 then break end
        local col=node.conflict and C.bad or node.localNode and C.good or C.white
        panel(mon,6,y,pw-12,17,nil)
        text(mon,12,y+6,gfx.fitText(tostring(node.hostname or node.key),130,1),col,1)
        text(mon,150,y+6,tostring(node.role or "?"),C.muted,1)
        text(mon,220,y+6,"CC:"..tostring(node.computerId or "?"),C.muted,1)
        button(mon,pw-78,y+2,66,13,"REBOOT",C.bad,"node_reboot",node.key,false)
        y=y+21
    end
    if y==24 then text(mon,8,y,"NO NODES DISCOVERED",C.muted,1) end
end

function M.init(mon,requestedMode)
    if type(mon.setGraphicsMode)~="function" or type(mon.drawPixels)~="function"
        or type(mon.setPixel)~="function" then error("CC:Graphics API not available") end
    mode=requestedMode or 1
    mon.setGraphicsMode(mode)
    local ok,w,h=pcall(mon.getSize,mode)
    if ok and tonumber(w) and tonumber(h) then pw,ph=w,h
    else local tw,th=mon.getSize(); pw,ph=tw*6,th*9 end
    if type(mon.setFrozen)=="function" then pcall(mon.setFrozen,false) end
end

function M.shutdown(mon)
    pcall(mon.setGraphicsMode,false)
end

function M.draw(mon,state)
    hitboxes={}
    local frozen=type(mon.setFrozen)=="function"
    if frozen then pcall(mon.setFrozen,true) end

    fill(mon,0,0,pw,ph,C.bg)
    local page=state.page or "home"
    if page=="machine" then drawMachine(mon,state)
    elseif page=="events" then drawEvents(mon,state)
    elseif page=="network" then drawNetwork(mon,state)
    else drawHome(mon,state) end
    drawNav(mon,state)

    if frozen then pcall(mon.setFrozen,false) end
end

function M.actionAt(x,y)
    return gfx.hit(hitboxes,x,y)
end

return M
