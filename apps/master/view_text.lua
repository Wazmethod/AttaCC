local M = {}

local hitboxes = {}

local function resetHits() hitboxes = {} end

local function writeAt(mon,x,y,value,fg,bg)
    local w,h=mon.getSize()
    if y<1 or y>h or x>w then return end
    local s=tostring(value or "")
    if #s>w-x+1 then s=s:sub(1,w-x+1) end
    mon.setCursorPos(math.max(1,x),y)
    if bg then mon.setBackgroundColor(bg) end
    mon.setTextColor(fg or colors.white)
    mon.write(s)
    if bg then mon.setBackgroundColor(colors.black) end
end

local function fill(mon,x,y,width,bg)
    local w,h=mon.getSize()
    if y<1 or y>h or width<=0 then return end
    width=math.min(width,w-x+1)
    if width<=0 then return end
    mon.setCursorPos(x,y)
    mon.setBackgroundColor(bg)
    mon.write(string.rep(" ",width))
    mon.setBackgroundColor(colors.black)
end

local function button(mon,x,y,width,label,bg,action,arg,active)
    fill(mon,x,y,width,active and colors.cyan or bg)
    local shown=tostring(label or "")
    local tx=x+math.max(0,math.floor((width-#shown)/2))
    writeAt(mon,tx,y,shown,colors.white,active and colors.cyan or bg)
    table.insert(hitboxes,{x1=x,x2=x+width-1,y=y,action=action,arg=arg})
end

local function levelColor(level)
    if level=="critical" then return colors.red end
    if level=="warning" then return colors.orange end
    if level=="success" then return colors.lime end
    return colors.lightBlue
end

local function selectedApp(state)
    for _,app in ipairs(state.apps or {}) do
        if app.key==state.selectedAppKey then return app end
    end
    return (state.apps or {})[1]
end

local NAV={{"home","HOME"},{"machine","MACHINE"},{"events","EVENTS"},{"network","NETWORK"}}

local function drawNav(mon,state)
    local w,h=mon.getSize()
    local gap=1
    local bw=math.max(7,math.floor((w-gap*(#NAV-1))/#NAV))
    local x=1
    for _,item in ipairs(NAV) do
        button(mon,x,h,bw,item[2],colors.blue,"page",item[1],state.page==item[1])
        x=x+bw+gap
    end
end

local function drawHeader(mon,title)
    local w=select(1,mon.getSize())
    fill(mon,1,1,w,colors.gray)
    writeAt(mon,2,1,"ATTACC MASTER",colors.cyan,colors.gray)
    writeAt(mon,math.max(16,math.floor((w-#title)/2)),1,title,colors.yellow,colors.gray)
end

local function drawHome(mon,state)
    local w,h=mon.getSize()
    drawHeader(mon,"HOME")
    local home=state.home or {}
    local y=3

    if home.machines~=false then
        writeAt(mon,2,y,"MACHINES",colors.yellow); y=y+1
        local apps=state.apps or {}
        if #apps==0 then
            writeAt(mon,3,y,"No controllable machine discovered",colors.orange); y=y+2
        else
            for i=1,math.min(#apps,math.max(1,math.floor((h-8)/2))) do
                local app=apps[i]
                local label=tostring(app.machineLabel or app.machine or app.title or app.key)
                writeAt(mon,3,y,(app.fresh and "[OK] " or "[--] ")..label,
                    app.fresh and colors.lime or colors.orange)
                y=y+1
            end
            y=y+1
        end
    end

    if home.network~=false and y<h-5 then
        writeAt(mon,2,y,"NETWORK",colors.yellow)
        writeAt(mon,14,y,tostring(#(state.nodes or {})).." discovered node(s)",colors.white)
        y=y+2
    end

    if home.storage~=false and y<h-5 then
        local s=state.storage or {}
        writeAt(mon,2,y,"STORAGE",colors.yellow)
        writeAt(mon,14,y,s.available and
            (string.upper(tostring(s.backend or "?")).."  "..tostring(s.keys or 0).." key(s)")
            or ("INACTIVE  "..tostring(s.error or "")),
            s.available and colors.lime or colors.orange)
        y=y+2
    end

    if home.web~=false and y<h-5 then
        local web=state.web or {}
        writeAt(mon,2,y,"WEB",colors.yellow)
        writeAt(mon,14,y,string.upper(tostring(web.status or "?")),web.status=="active" and colors.lime or colors.orange)
        y=y+2
    end

    if home.events~=false and y<h-3 then
        writeAt(mon,2,y,"RECENT EVENTS",colors.yellow); y=y+1
        for i=1,math.min(3,#(state.events or {}),h-y-1) do
            local e=state.events[i]
            writeAt(mon,3,y,
                tostring(e.hostname or e.machine or "?").."  "..tostring(e.code or "EVENT").."  "..tostring(e.message or ""),
                levelColor(e.level))
            y=y+1
        end
    end
end

local function flattenMetrics(app)
    local out={}
    local ui=app and app.data and app.data.ui
    for _,group in ipairs(ui and type(ui.groups)=="table" and ui.groups or {}) do
        for _,metric in ipairs(type(group.metrics)=="table" and group.metrics or {}) do
            table.insert(out,{
                group=group.title or group.id,
                label=metric.label,
                value=metric.value,
                unit=metric.unit,
            })
        end
    end
    if #out==0 then
        for _,metric in ipairs(ui and type(ui.metrics)=="table" and ui.metrics or {}) do
            table.insert(out,{group="SUMMARY",label=metric.label,value=metric.value,unit=metric.unit})
        end
    end
    return out
end

local function drawMachineSelector(mon,state,startY)
    local w=select(1,mon.getSize())
    local apps=state.apps or {}
    if #apps==0 then
        writeAt(mon,2,startY,"No controllable machine",colors.orange)
        return startY+2
    end
    local width=math.max(10,math.floor((w-1)/math.min(#apps,4)))
    local x=1
    for i=1,math.min(#apps,4) do
        local app=apps[i]
        local label=tostring(app.machineLabel or app.machine or app.title):sub(1,width-2)
        button(mon,x,startY,width,label,app.fresh and colors.blue or colors.orange,
            "machine_select",app.key,app.key==state.selectedAppKey)
        x=x+width
    end
    return startY+2
end

local function drawMachine(mon,state)
    local w,h=mon.getSize()
    drawHeader(mon,"MACHINE")
    local y=drawMachineSelector(mon,state,3)
    local app=selectedApp(state)
    if not app then return end

    local tabs={{"data","DATA"},{"graphs","GRAPHS"},{"controls","CONTROLS"}}
    local bw=math.max(10,math.floor((w-2)/3))
    local x=1
    for _,tab in ipairs(tabs) do
        button(mon,x,y,bw,tab[2],colors.gray,"machine_tab",tab[1],state.machineTab==tab[1])
        x=x+bw+1
    end
    y=y+2

    writeAt(mon,2,y,tostring(app.machineLabel or app.machine),app.fresh and colors.lime or colors.orange)
    writeAt(mon,math.max(20,w-20),y,tostring(app.module or ""),colors.gray)
    y=y+2

    if state.machineTab=="controls" then
        local controls=app.data and app.data.ui and app.data.ui.controls or {}
        local row=y
        for _,control in ipairs(controls) do
            if row>=h-1 then break end
            local tone=control.tone=="bad" and colors.red
                or control.tone=="warn" and colors.orange
                or control.tone=="good" and colors.green
                or colors.blue
            button(mon,2,row,math.max(12,w-3),tostring(control.label or control.command),tone,"command",control,false)
            row=row+2
        end
        if #controls==0 then writeAt(mon,2,row,"No controls exported",colors.gray) end

    elseif state.machineTab=="graphs" then
        local row=y
        local ids={}
        for id in pairs(app.history or {}) do table.insert(ids,id) end
        table.sort(ids)
        for _,id in ipairs(ids) do
            if row>=h-1 then break end
            local samples=app.history[id] or {}
            local min,max,last=nil,nil,nil
            for _,s in ipairs(samples) do
                local v=tonumber(s.value)
                if v then
                    min=min and math.min(min,v) or v
                    max=max and math.max(max,v) or v
                    last=v
                end
            end
            local meta=samples[#samples] or {}
            writeAt(mon,2,row,string.format("%-14s now=%s  min=%s  max=%s %s",
                tostring(meta.label or id),
                last and string.format("%.1f",last) or "-",
                min and string.format("%.1f",min) or "-",
                max and string.format("%.1f",max) or "-",
                tostring(meta.unit or "")),colors.white)
            row=row+1
        end
        if #ids==0 then writeAt(mon,2,row,"Waiting for numeric history...",colors.gray) end

    else
        local metrics=flattenMetrics(app)
        local row=y
        local lastGroup=nil
        for _,m in ipairs(metrics) do
            if row>=h-1 then break end
            if m.group~=lastGroup then
                writeAt(mon,2,row,string.upper(tostring(m.group or "")),colors.yellow)
                lastGroup=m.group
                row=row+1
            end
            if row>=h-1 then break end
            writeAt(mon,4,row,string.format("%-12s %s%s",
                tostring(m.label or "?"),tostring(m.value or "-"),
                m.unit and (" "..tostring(m.unit)) or ""),colors.white)
            row=row+1
        end
    end

    if state.pending then
        writeAt(mon,math.max(2,w-24),h-1,"WAIT ACK "..tostring(state.pending.command),colors.orange)
    end
end

local function drawEvents(mon,state)
    local w,h=mon.getSize()
    drawHeader(mon,"EVENTS")
    local y=3
    for i=1,math.min(#(state.events or {}),h-4) do
        local e=state.events[i]
        local line=tostring(e.hostname or e.machine or "?").." | "
            ..tostring(e.code or "EVENT").." | "..tostring(e.message or "")
        writeAt(mon,2,y,line:sub(1,w-2),levelColor(e.level))
        y=y+1
    end
    if y==3 then writeAt(mon,2,y,"No events",colors.gray) end
end

local function drawNetwork(mon,state)
    local w,h=mon.getSize()
    drawHeader(mon,"NETWORK")
    local y=3
    for _,node in ipairs(state.nodes or {}) do
        if y>=h-1 then break end
        local status=node.conflict and "CONFLICT" or node.localNode and "LOCAL" or "ONLINE"
        writeAt(mon,2,y,string.format("%-20s %-10s %-9s cc:%s",
            tostring(node.hostname or node.key),tostring(node.role or "?"),status,
            tostring(node.computerId or "?")),
            node.conflict and colors.red or node.localNode and colors.lime or colors.white)
        button(mon,math.max(2,w-10),y,9,"REBOOT",colors.red,"node_reboot",node.key,false)
        y=y+1
    end
    if y==3 then writeAt(mon,2,y,"No nodes discovered",colors.gray) end
end

function M.draw(mon,state)
    resetHits()
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
    mon.setCursorPos(1,1)

    local page=state.page or "home"
    if page=="machine" then drawMachine(mon,state)
    elseif page=="events" then drawEvents(mon,state)
    elseif page=="network" then drawNetwork(mon,state)
    else drawHome(mon,state) end

    drawNav(mon,state)
end

function M.actionAt(x,y)
    for _,h in ipairs(hitboxes) do
        if x>=h.x1 and x<=h.x2 and y==h.y then return h.action,h.arg end
    end
    return nil
end

return M
