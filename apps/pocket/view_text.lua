local dashboard = require("lib.dashboard")
local pocketPages = require("lib.pocket_pages")
local M = {}

local function wh() return term.getSize() end

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
    return pocketPages.build(data)
end

function M.pageCount(data) return math.max(1,#buildPages(data)) end

local function pageDef(page,data)
    local pages=buildPages(data)
    page=math.max(1,math.min(tonumber(page) or 1,#pages))
    return pages[page],pages
end

local function header(page,data,masterAlive,sourceFresh,pending)
    local w=wh()
    fill(1,1,w,colors.gray)
    local app=data and data.ui and data.ui.app
    local title=(app and app.title) or "ATTACC POCKET"
    put(2,1,tostring(title):sub(1,math.max(1,w-10)),colors.yellow,colors.gray)
    local status=pending and colors.orange
        or (not masterAlive and colors.red)
        or (sourceFresh and colors.lime or colors.orange)
    fill(w,1,1,status)
end

local function footer(page,data)
    local w,h=wh()
    local def,pages=pageDef(page,data)
    fill(1,h,w,colors.gray)
    put(1,h,"<",colors.white,colors.gray)
    put(w,h,">",colors.white,colors.gray)
    local meta=dashboard.pageLabel(def).." "..tostring(page).."/"..tostring(#pages)
    put(math.max(2,math.floor((w-#meta)/2)+1),h,meta,colors.lightGray,colors.gray)
end

local function drawHome(data,sourceFresh,masterAlive,apps)
    center(3,masterAlive and "MASTER ONLINE" or "MASTER OFFLINE",
        masterAlive and colors.green or colors.red)
    put(2,5,"Machines   "..tostring(#(apps or {})),colors.white)
    if data then
        local ui=data.ui or {}
        put(2,6,"Selected   "..tostring(ui.app and (ui.app.machineLabel or ui.app.title) or "?"),colors.white)
        put(2,7,"State      "..tostring(ui.state or "UNKNOWN"),
            sourceFresh and colors.lime or colors.orange)
    else
        put(2,6,"No machine telemetry",colors.orange)
    end
end

local function drawMachines(apps,selectedKey)
    local _,h=wh()
    put(2,3,"SELECT MACHINE",colors.yellow)
    local y=5
    for _,app in ipairs(apps or {}) do
        if y>=h then break end
        local selected=app.key==selectedKey
        fill(1,y,select(1,wh()),selected and colors.blue or colors.black)
        put(2,y,(selected and "[X] " or "[ ] ")..
            tostring(app.machineLabel or app.machine or app.title or app.key),
            selected and colors.white or (app.fresh and colors.lime or colors.orange),
            selected and colors.blue or colors.black)
        y=y+1
    end
end

local function drawData(def)
    put(2,3,dashboard.pageLabel(def),colors.yellow)
    put(2,4,"< SUBPAGE "..tostring(def.subIndex or 1).."/"..tostring(def.subTotal or 1).." >",colors.lightGray)
    local y=5
    for _,m in ipairs(def.items or {}) do
        if y>=select(2,wh()) then break end
        local value=tostring(m.value or "-")..(m.unit and (" "..tostring(m.unit)) or "")
        put(2,y,string.format("%-10s %s",tostring(m.label or "?"),value),colors.white)
        y=y+1
    end
end

local function drawGraphs(def)
    local w,h=wh()
    put(2,3,dashboard.pageLabel(def),colors.yellow)
    local y=5
    for _,graph in ipairs(def.items or {}) do
        if y+2>=h then break end
        local value=tonumber(graph.value) or 0
        local lo=tonumber(graph.min) or 0
        local hi=tonumber(graph.max) or math.max(1,value)
        if hi<=lo then hi=lo+1 end
        local ratio=math.max(0,math.min(1,(value-lo)/(hi-lo)))
        local barW=math.max(4,w-4)
        local filled=math.floor(barW*ratio)
        put(2,y,tostring(graph.label or graph.id or "GRAPH").." "
            ..string.format("%.1f",value)..(graph.unit and (" "..tostring(graph.unit)) or ""),colors.white)
        put(2,y+1,string.rep("#",filled)..string.rep("-",barW-filled),colors.lightBlue)
        y=y+3
    end
end

local function drawControls(def)
    local w,h=wh()
    put(2,3,dashboard.pageLabel(def),colors.yellow)
    local y=5
    for _,control in ipairs(def.items or {}) do
        if y>=h then break end
        local bg=control.tone=="bad" and colors.red
            or control.tone=="warn" and colors.orange
            or control.tone=="good" and colors.green or colors.blue
        fill(1,y,w,bg)
        put(2,y,tostring(control.label or control.command),colors.white,bg)
        y=y+2
    end
end

local function drawEvents(events)
    local w,h=wh()
    put(2,3,"EVENTS",colors.yellow)
    local y=5
    for i=1,math.min(#(events or {}),h-6) do
        local e=events[i]
        local col=e.level=="critical" and colors.red or e.level=="warning" and colors.orange
            or e.level=="success" and colors.lime or colors.lightBlue
        put(1,y,(tostring(e.hostname or e.machine or "?").." "..tostring(e.code or "EVENT")):sub(1,w),col)
        y=y+1
    end
end

local function drawSystem(nodes,selected,confirming,masterAlive)
    put(2,3,"POCKET SYSTEM",colors.yellow)
    put(2,5,"Computer ID "..tostring(os.getComputerID()),colors.white)
    put(2,6,"Master      "..(masterAlive and "ONLINE" or "OFFLINE"),
        masterAlive and colors.lime or colors.red)
    put(2,7,"Nodes       "..tostring(#(nodes or {})),colors.white)
    local _,h=wh()
    local y=9
    for _,node in ipairs(nodes or {}) do
        if y>=h-3 then break end
        put(2,y,(selected and selected[node.key] and "[X] " or "[ ] ")..tostring(node.label or node.hostname or node.key),colors.white)
        y=y+1
    end
    put(2,h-2,confirming and "CONFIRM REBOOT" or "REBOOT SELECTED",confirming and colors.red or colors.orange)
end

function M.draw(page,data,events,masterAlive,sourceFresh,pending,toast,toastColor,nodes,selected,confirming,apps,selectedAppKey)
    if type(term.setGraphicsMode)=="function" then pcall(term.setGraphicsMode,false) end
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()

    header(page,data,masterAlive,sourceFresh,pending)
    local def=pageDef(page,data)

    if def.kind=="home" then drawHome(data,sourceFresh,masterAlive,apps)
    elseif def.kind=="machines" then drawMachines(apps,selectedAppKey)
    elseif def.kind=="data" then drawData(def)
    elseif def.kind=="graphs" then drawGraphs(def)
    elseif def.kind=="controls" then drawControls(def)
    elseif def.kind=="events" then drawEvents(events)
    elseif def.kind=="system" then drawSystem(nodes,selected,confirming,masterAlive)
    end

    local w,h=wh()
    if toast then put(1,h-1,tostring(toast):sub(1,w),toastColor or colors.white) end
    footer(page,data)
end

function M.click(page,data,x,y,nodes,selected,apps,selectedAppKey)
    local w,h=wh()
    local def,pages=pageDef(page,data)

    if y==h then
        if x<=math.floor(w/3) then
            return "page",page>1 and page-1 or #pages
        elseif x>=math.ceil(w*2/3) then
            return "page",page<#pages and page+1 or 1
        end
    end

    if def.subTotal and def.subTotal > 1 and y==4 then
        return "subpage", { kind=def.kind, delta=x<=math.floor(w/2) and -1 or 1 }
    end

    if def.kind=="machines" then
        local row=5
        for _,app in ipairs(apps or {}) do
            if y==row then return "app_select",app.key end
            row=row+1
        end
    elseif def.kind=="controls" then
        local row=5
        for _,control in ipairs(def.items or {}) do
            if y==row or y==row+1 then return "command",control end
            row=row+2
        end
    elseif def.kind=="system" then
        if y==h-2 then return "node_reboot_selected" end
        local row=9
        for _,node in ipairs(nodes or {}) do
            if y==row then return "node_toggle",node.key end
            row=row+1
            if row>=h-3 then break end
        end
    elseif def.kind=="events" then
        local row=5
        for _,e in ipairs(events or {}) do
            if y==row and e.machine then return "event_machine",e.machine end
            row=row+1
        end
    end

    return nil
end

return M
