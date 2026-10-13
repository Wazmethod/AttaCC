local config = require("lib.config")
local M = {}

local PAGE_DEFS = {
    status = "STATUS",
    control = "CONTROL",
    motor = "MOTOR",
    events = "EVENTS",
    system = "SYSTEM",
}

local function configuredPages()
    local source = config.pocket and config.pocket.pages
    local out = {}
    for _, page in ipairs(type(source) == "table" and source or {}) do
        if PAGE_DEFS[page] then table.insert(out, page) end
    end
    if #out == 0 then out = { "status" } end
    return out
end

local pages = configuredPages()
M.pageCount = #pages

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

local function bar(y,label,value,color)
    local w=wh()
    local pct=math.max(0,math.min(100,tonumber(value) or 0))
    local val=string.format("%3.0f%%",pct)
    local start=#label+2
    local width=math.max(3,w-start-#val)
    local n=math.floor(width*pct/100+0.5)
    put(1,y,label,colors.lightGray)
    if n>0 then fill(start,y,n,color) end
    if width-n>0 then fill(start+n,y,width-n,colors.gray) end
    put(start+width+1,y,val,colors.white)
end

local function header(page,masterAlive,collectorFresh,pending)
    local w=wh()
    fill(1,1,w,colors.gray)
    put(2,1,"STEAM",colors.yellow,colors.gray)

    local pageId=pages[page] or pages[1]
    local name=PAGE_DEFS[pageId] or "?"
    put(math.max(7,math.floor((w-#name)/2)+1),1,name,colors.white,colors.gray)

    local c=pending and colors.orange
        or (not masterAlive and colors.red)
        or (collectorFresh and colors.lime or colors.orange)
    fill(w,1,1,c)
end

local function footer(page)
    local w,h=wh()
    fill(1,h,w,colors.gray)
    put(1,h,"<",colors.white,colors.gray)
    put(w,h,">",colors.white,colors.gray)
    local p=tostring(page).."/"..tostring(M.pageCount)
    put(math.max(2,math.floor((w-#p)/2)+1),h,p,colors.lightGray,colors.gray)
end

local function statusPage(data,collectorFresh)
    local state=data and data.plant and data.plant.status or "NO DATA"
    local bg=(state=="RUNNING" or state=="ONLINE") and colors.green
        or (state=="STARTING" or state=="DEGRADED") and colors.orange
        or colors.red

    center(3,collectorFresh and state or "DATA STALE",collectorFresh and bg or colors.red)

    if not data then
        put(2,5,"Waiting telemetry...",colors.orange)
        return
    end

    put(2,5,"KINETIC",colors.yellow)
    put(2,6,string.format("RPM   %7.1f",data.power.rpm or 0))
    put(2,7,string.format("LOAD  %6.1f%%",data.power.load or 0))
    put(2,8,string.format("SU %.0f/%.0f",data.power.stress or 0,data.power.capacity or 0),colors.lightGray)

    put(2,10,"BOILER",colors.yellow)
    bar(11,"W",data.boiler.water,colors.blue)
    bar(12,"H",data.boiler.heat,colors.red)

    put(2,14,"ENERGY",colors.yellow)
    bar(15,"B",data.battery.percent,colors.lime)

    put(2,17,"CTRL "..tostring(data.control.state),colors.lightGray)
    put(2,18,"AUTO "..(data.control.armed and "ARMED" or "DISARMED"),
        data.control.armed and colors.lime or colors.red)
end

local function controlPage(data)
    if not data then put(2,4,"No collector data",colors.red) return end

    put(2,3,"STARTUP",colors.yellow)
    center(5,"AUTO START",colors.green)
    center(7,"ABORT",colors.red)
    center(9,data.control.armed and "DISARM AUTO" or "ARM AUTO",
        data.control.armed and colors.orange or colors.green)

    put(2,11,"CLUTCHES",colors.yellow)
    center(13,"MAIN "..(data.control.mainClutchEngaged and "ON" or "CUT"),
        data.control.mainClutchEngaged and colors.green or colors.red)
    center(15,"GEN  "..(data.control.genClutchEngaged and "ON" or "CUT"),
        data.control.genClutchEngaged and colors.green or colors.red)
    center(17,"ALT  "..(data.control.alternatorClutchEngaged and "ON" or "CUT"),
        data.control.alternatorClutchEngaged and colors.green or colors.red)
end

local function motorPage(data)
    if not data then put(2,4,"No collector data",colors.red) return end
    local w=wh()

    put(2,3,"ELECTRIC MOTOR",colors.yellow)
    put(2,5,string.format("RPM  %7.1f",data.motor.rpm or 0))
    put(2,6,string.format("DRAW %7.0f FE/t",data.motor.consumption or 0))
    bar(8,"BAT",data.battery.percent,colors.lime)

    local lw=math.floor((w-1)/2)
    local rx=lw+2
    local rw=w-rx+1

    fill(1,11,lw,colors.blue); put(2,11,"32 RPM",colors.white,colors.blue)
    fill(rx,11,rw,colors.blue); put(rx+1,11,"64 RPM",colors.white,colors.blue)
    fill(1,13,lw,colors.cyan); put(2,13,"128 RPM",colors.black,colors.cyan)
    fill(rx,13,rw,colors.red); put(rx+1,13,"STOP",colors.white,colors.red)

    center(16,"RUN TOPOLOGY",colors.blue)
    center(18,"ALL CUT",colors.orange,colors.black)
end

local function eventsPage(events)
    local w,h=wh()
    put(2,3,"EVENT BUS",colors.yellow)

    if not events or #events==0 then
        put(2,5,"No events",colors.lightGray)
        return
    end

    local maxRows=h-5
    for i=1,math.min(#events,maxRows) do
        local e=events[i]
        local c=e.level=="critical" and colors.red
            or e.level=="warning" and colors.orange
            or e.level=="success" and colors.lime
            or colors.lightBlue
        put(1,3+i,tostring(e.code or e.message or "EVENT"):sub(1,w),c)
    end
end

local function systemPage(nodes,selected,confirming)
    local w,h=wh()
    put(2,3,"MACHINE NETWORK",colors.yellow)

    local row=5
    local maxRows=h-8
    for i=1,math.min(#(nodes or {}),maxRows) do
        local node=nodes[i]
        local on=selected and selected[node.key]
        fill(1,row,w,on and colors.blue or colors.black)
        put(2,row,(on and "[X] " or "[ ] ")..tostring(node.label or node.key),
            node.localNode and colors.cyan or colors.white,
            on and colors.blue or colors.black)
        row=row+1
    end

    if #(nodes or {})==0 then
        put(2,5,"No nodes discovered",colors.orange)
    end

    local half=math.floor((w-1)/2)
    fill(1,h-6,half,colors.blue)
    put(2,h-6,"SHELL",colors.white,colors.blue)
    fill(half+2,h-6,w-half-1,colors.cyan)
    put(half+3,h-6,"SWITCH UI",colors.black,colors.cyan)

    center(h-3,confirming and "CONFIRM REBOOT" or "REBOOT SELECTED",
        confirming and colors.red or colors.orange)
end

function M.draw(page,data,events,masterAlive,collectorFresh,pending,toast,toastColor,nodes,selected,confirming)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()

    header(page,masterAlive,collectorFresh,pending)

    local pageId=pages[page] or pages[1]
    if pageId=="status" then statusPage(data,collectorFresh)
    elseif pageId=="control" then controlPage(data)
    elseif pageId=="motor" then motorPage(data)
    elseif pageId=="events" then eventsPage(events)
    elseif pageId=="system" then systemPage(nodes or {},selected or {},confirming)
    end

    local w,h=wh()
    if toast then
        fill(1,h-1,w,colors.black)
        put(1,h-1,tostring(toast):sub(1,w),toastColor or colors.white)
    end

    footer(page)
end

function M.click(page,data,x,y,nodes,selected)
    local w,h=wh()

    if y==h then
        if x<=math.floor(w/3) then
            local p=page-1
            if p<1 then p=M.pageCount end
            return "page",p
        elseif x>=math.ceil(w*2/3) then
            local p=page+1
            if p>M.pageCount then p=1 end
            return "page",p
        end
    end

    local pageId=pages[page] or pages[1]

    if pageId=="status" then
        return nil
    elseif pageId=="control" and data then
        if y==5 then return "command",{command="procedure"}
        elseif y==7 then return "command",{command="abort"}
        elseif y==9 then return "command",{command=data.control.armed and "disarm" or "arm"}
        elseif y==13 then return "command",{command=data.control.mainClutchEngaged and "main_off" or "main_on"}
        elseif y==15 then return "command",{command=data.control.genClutchEngaged and "gen_off" or "gen_on"}
        elseif y==17 then return "command",{command=data.control.alternatorClutchEngaged and "alt_off" or "alt_on"} end
    elseif pageId=="motor" and data then
        local lw=math.floor((w-1)/2)
        local rx=lw+2
        if y==11 then
            if x<=lw then return "command",{command="motor_speed",rpm=32}
            elseif x>=rx then return "command",{command="motor_speed",rpm=64} end
        elseif y==13 then
            if x<=lw then return "command",{command="motor_speed",rpm=128}
            elseif x>=rx then return "command",{command="motor_stop"} end
        elseif y==16 then return "command",{command="running_topology"}
        elseif y==18 then return "command",{command="all_cut"} end
    elseif pageId=="system" then
        local row=5
        for i,node in ipairs(nodes or {}) do
            if y==row then return "node_toggle",node.key end
            row=row+1
        end
        if y==h-6 then
            if x<=math.floor((w-1)/2) then return "open_shell"
            else return "toggle_ui" end
        end
        if y==h-3 then return "node_reboot_selected" end
    end

    return nil
end

return M
