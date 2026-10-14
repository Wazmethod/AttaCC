local uiPages = require("lib.ui_pages")
local M = {}

local function wh()
    return term.getSize()
end

local function put(x,y,s,fg,bg)
    local w,h=wh()
    if y<1 or y>h or x>w then return end
    s=tostring(s or "")
    if #s>w-x+1 then s=s:sub(1,w-x+1) end
    term.setCursorPos(math.max(1,x),y)
    if bg then term.setBackgroundColor(bg) end
    term.setTextColor(fg or colors.white)
    term.write(s)
    if bg then term.setBackgroundColor(colors.black) end
end

local function fill(x,y,width,bg)
    local w,h=wh()
    if y<1 or y>h or width<=0 or x>w then return end
    width=math.min(width,w-x+1)
    term.setCursorPos(x,y)
    term.setBackgroundColor(bg)
    term.write(string.rep(" ",width))
    term.setBackgroundColor(colors.black)
end

local function center(y,label,bg,fg)
    local w=wh()
    fill(1,y,w,bg)
    put(math.max(1,math.floor((w-#label)/2)+1),y,label,fg or colors.white,bg)
end

local function buildPages(data)
    return uiPages.pocketPages(data, {
        groupMetrics = 4,
        groupControls = 4,
        graphs = 3,
    })
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

local function header(page,data,masterAlive,sourceFresh,pending)
    local w=wh()
    fill(1,1,w,colors.gray)
    local app=data and data.ui and data.ui.app
    local title=(app and app.title) or (data and data.ui and data.ui.title) or "ATTACC"
    put(2,1,tostring(title):sub(1,math.max(1,w-10)),colors.yellow,colors.gray)

    local def=pageDef(page,data)
    local status=pending and colors.orange
        or (not masterAlive and colors.red)
        or (sourceFresh and colors.lime or colors.orange)
    fill(w,1,1,status)
    return def
end

local function footer(page,data)
    local w,h=wh()
    local def,pages=pageDef(page,data)
    fill(1,h,w,colors.gray)
    put(1,h,"<",colors.white,colors.gray)
    put(w,h,">",colors.white,colors.gray)
    local label=uiPages.pageLabel(def)
    local meta=label.."  "..tostring(page).."/"..tostring(#pages)
    put(math.max(2,math.floor((w-#meta)/2)+1),h,meta,colors.lightGray,colors.gray)
end

local function findGroup(data,id)
    local groups=data and data.ui and data.ui.groups
    for _,group in ipairs(type(groups)=="table" and groups or {}) do
        if tostring(group.id)==tostring(id) then return group end
    end
    return nil
end

local function controlsForGroup(data,id)
    local out={}
    local controls=data and data.ui and data.ui.controls
    for _,control in ipairs(type(controls)=="table" and controls or {}) do
        if tostring(control.group or "default")==tostring(id) then
            table.insert(out,control)
        end
    end
    return out
end

local function drawHome(data,sourceFresh,def)
    if not data then
        center(3,"NO TELEMETRY",colors.red)
        put(2,5,"Waiting for controllable machine data...",colors.orange)
        return
    end

    local ui=data.ui or {}
    local state=tostring(ui.state or (data.plant and data.plant.status) or "UNKNOWN")
    center(3,sourceFresh and state or "DATA STALE",
        sourceFresh and colors.green or colors.red)

    local metrics=def and type(def.metrics)=="table" and def.metrics
        or (type(ui.metrics)=="table" and ui.metrics or {})
    local y=5
    for i=1,math.min(#metrics,8) do
        local m=metrics[i]
        local value=tostring(m.value or "-")
        if m.unit and m.unit~="" then value=value.." "..tostring(m.unit) end
        put(2,y,string.format("%-10s %s",tostring(m.label or "?"),value),colors.white)
        y=y+1
    end
end

local function drawGroup(data,def)
    local group=def and def.group
    if not group then
        put(2,4,"Group unavailable",colors.orange)
        return
    end

    put(2,3,string.upper(uiPages.pageLabel(def)),colors.yellow)
    local y=5
    for i,m in ipairs(type(def.metrics)=="table" and def.metrics or {}) do
        if y>=9 then break end
        local value=tostring(m.value or "-")
        if m.unit and m.unit~="" then value=value.." "..tostring(m.unit) end
        put(2,y,string.format("%-9s %s",tostring(m.label or "?"),value),colors.white)
        y=y+1
    end

    local w,h=wh()
    local controls=type(def.controls)=="table" and def.controls or {}
    local startY=10
    local leftW=math.floor((w-1)/2)
    local rightX=leftW+2

    for i,control in ipairs(controls) do
        local row=math.floor((i-1)/2)
        local yy=startY+row*2
        if yy>=h then break end
        local left=(i%2)==1
        local x=left and 1 or rightX
        local width=left and leftW or (w-rightX+1)
        local bg=control.tone=="bad" and colors.red
            or control.tone=="warn" and colors.orange
            or control.tone=="good" and colors.green
            or colors.blue
        fill(x,yy,width,bg)
        put(x+1,yy,tostring(control.label or control.command),colors.white,bg)
    end
end

local function drawGraphs(def)
    local w,h=wh()
    put(2,3,uiPages.pageLabel(def),colors.yellow)
    local y=5
    for _,graph in ipairs(def and def.graphs or {}) do
        if y+2>=h then break end
        local value=tonumber(graph.value) or 0
        local lo=tonumber(graph.min) or 0
        local hi=tonumber(graph.max) or math.max(1,value)
        if hi<=lo then hi=lo+1 end
        local ratio=math.max(0,math.min(1,(value-lo)/(hi-lo)))
        local barW=math.max(4,w-4)
        local filled=math.floor(barW*ratio)
        put(2,y,tostring(graph.label or graph.id or "GRAPH").." "
            ..string.format("%.1f",value)
            ..(graph.unit and (" "..tostring(graph.unit)) or ""),colors.white)
        put(2,y+1,string.rep("#",filled)..string.rep("-",barW-filled),colors.lightBlue)
        y=y+3
    end
end

local function drawMachines(apps,selectedKey)
    local _,h=wh()
    put(2,3,"CONTROLLABLE MACHINES",colors.yellow)
    if type(apps)~="table" or #apps==0 then
        put(2,5,"No controllable apps discovered",colors.orange)
        return
    end

    local y=5
    for _,app in ipairs(apps) do
        if y>=h then break end
        local selected=app.key==selectedKey
        fill(1,y,select(1,wh()),selected and colors.blue or colors.black)
        local label=tostring(app.machineLabel or app.machine or app.title or app.key)
        put(2,y,(selected and "[X] " or "[ ] ")..label,
            selected and colors.white or (app.fresh and colors.lime or colors.orange),
            selected and colors.blue or colors.black)
        y=y+1
    end
end

local function drawEvents(events)
    local w,h=wh()
    put(2,3,"EVENTS",colors.yellow)
    if type(events)~="table" or #events==0 then
        put(2,5,"No events",colors.lightGray)
        return
    end
    local y=5
    for i=1,math.min(#events,h-6) do
        local e=events[i]
        local col=e.level=="critical" and colors.red
            or e.level=="warning" and colors.orange
            or e.level=="success" and colors.lime
            or colors.lightBlue
        put(1,y,tostring(e.code or e.message or "EVENT"):sub(1,w),col)
        y=y+1
    end
end

local function drawSystem(nodes,selected,confirming)
    local w,h=wh()
    put(2,3,"NETWORK NODES",colors.yellow)
    local y=5
    for _,node in ipairs(nodes or {}) do
        if y>=h-3 then break end
        local on=selected and selected[node.key]
        fill(1,y,w,on and colors.blue or colors.black)
        put(2,y,(on and "[X] " or "[ ] ")..tostring(node.label or node.key),
            node.localNode and colors.cyan or colors.white,
            on and colors.blue or colors.black)
        y=y+1
    end
    center(h-2,confirming and "CONFIRM REBOOT" or "REBOOT SELECTED",
        confirming and colors.red or colors.orange)
end

function M.draw(page,data,events,masterAlive,sourceFresh,pending,toast,toastColor,nodes,selected,confirming,apps,selectedAppKey)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()

    local def=header(page,data,masterAlive,sourceFresh,pending)
    if def.kind=="home" then drawHome(data,sourceFresh,def)
    elseif def.kind=="group" then drawGroup(data,def)
    elseif def.kind=="graphs" then drawGraphs(def)
    elseif def.kind=="machines" then drawMachines(apps,selectedAppKey)
    elseif def.kind=="events" then drawEvents(events)
    elseif def.kind=="system" then drawSystem(nodes or {},selected or {},confirming)
    end

    local w,h=wh()
    if toast then
        fill(1,h-1,w,colors.black)
        put(1,h-1,tostring(toast):sub(1,w),toastColor or colors.white)
    end
    footer(page,data)
end

function M.click(page,data,x,y,nodes,selected,apps,selectedAppKey)
    local w,h=wh()
    local def,pages=pageDef(page,data)

    if y==h then
        if x<=math.floor(w/3) then
            local p=page-1
            if p<1 then p=#pages end
            return "page",p
        elseif x>=math.ceil(w*2/3) then
            local p=page+1
            if p>#pages then p=1 end
            return "page",p
        end
    end

    if def.kind=="group" then
        local controls=type(def.controls)=="table" and def.controls or {}
        local startY=10
        local leftW=math.floor((w-1)/2)
        local rightX=leftW+2
        for i,control in ipairs(controls) do
            local row=math.floor((i-1)/2)
            local yy=startY+row*2
            if yy>=h then break end
            if y==yy then
                local left=(i%2)==1
                if (left and x<=leftW) or ((not left) and x>=rightX) then
                    return "command",control
                end
            end
        end
    elseif def.kind=="machines" then
        local row=5
        for _,app in ipairs(apps or {}) do
            if y==row then return "app_select",app.key end
            row=row+1
        end
    elseif def.kind=="system" then
        local row=5
        for _,node in ipairs(nodes or {}) do
            if y==row then return "node_toggle",node.key end
            row=row+1
        end
        if y==h-2 then return "node_reboot_selected" end
    end

    return nil
end

return M
