local M = {}
M.pageCount = 5

local pw, ph = 0, 0
local hitboxes = {}
local graphicsMode = 1
local handSignature = nil

local C = {
    bg = colors.black,
    panel = colors.gray,
    border = colors.lightGray,
    good = colors.lime,
    warn = colors.orange,
    bad = colors.red,
    accent = colors.cyan,
    blue = colors.blue,
    yellow = colors.yellow,
    white = colors.white,
    muted = colors.lightGray,
}

local FONT = {
    ["A"]={"010","101","111","101","101"}, ["B"]={"110","101","110","101","110"},
    ["C"]={"011","100","100","100","011"}, ["D"]={"110","101","101","101","110"},
    ["E"]={"111","100","110","100","111"}, ["F"]={"111","100","110","100","100"},
    ["G"]={"011","100","101","101","011"}, ["H"]={"101","101","111","101","101"},
    ["I"]={"111","010","010","010","111"}, ["J"]={"001","001","001","101","010"},
    ["K"]={"101","101","110","101","101"}, ["L"]={"100","100","100","100","111"},
    ["M"]={"101","111","111","101","101"}, ["N"]={"101","111","111","111","101"},
    ["O"]={"010","101","101","101","010"}, ["P"]={"110","101","110","100","100"},
    ["Q"]={"010","101","101","111","011"}, ["R"]={"110","101","110","101","101"},
    ["S"]={"011","100","010","001","110"}, ["T"]={"111","010","010","010","010"},
    ["U"]={"101","101","101","101","111"}, ["V"]={"101","101","101","101","010"},
    ["W"]={"101","101","111","111","101"}, ["X"]={"101","101","010","101","101"},
    ["Y"]={"101","101","010","010","010"}, ["Z"]={"111","001","010","100","111"},
    ["0"]={"111","101","101","101","111"}, ["1"]={"010","110","010","010","111"},
    ["2"]={"110","001","010","100","111"}, ["3"]={"110","001","010","001","110"},
    ["4"]={"101","101","111","001","001"}, ["5"]={"111","100","110","001","110"},
    ["6"]={"011","100","110","101","010"}, ["7"]={"111","001","010","010","010"},
    ["8"]={"010","101","010","101","010"}, ["9"]={"010","101","011","001","110"},
    ["."]={"000","000","000","000","010"}, [":"]={"000","010","000","010","000"},
    ["-"]={"000","000","111","000","000"}, ["/"]={"001","001","010","100","100"},
    ["%"]={"101","001","010","100","101"}, [" "]={"000","000","000","000","000"},
    ["["]={"110","100","100","100","110"}, ["]"]={"011","001","001","001","011"},
    ["_"]={"000","000","000","000","111"}, ["#"]={"101","111","101","111","101"},
}

local function fill(x,y,w,h,color)
    if w<=0 or h<=0 then return end
    term.drawPixels(math.floor(x),math.floor(y),color,math.floor(w),math.floor(h))
end

local function frame(x,y,w,h,color)
    fill(x,y,w,1,color); fill(x,y+h-1,w,1,color)
    fill(x,y,1,h,color); fill(x+w-1,y,1,h,color)
end

local function textWidth(value,scale)
    return #tostring(value or "") * 4 * (scale or 1)
end

local function text(x,y,value,color,scale)
    value=tostring(value or ""):upper()
    scale=scale or 1
    local cx=x

    for i=1,#value do
        local glyph=FONT[value:sub(i,i)] or {"111","101","101","101","111"}
        for gy=1,5 do
            for gx=1,3 do
                if glyph[gy]:sub(gx,gx)=="1" then
                    fill(cx+(gx-1)*scale,y+(gy-1)*scale,scale,scale,color)
                end
            end
        end
        cx=cx+4*scale
    end
end

local function addHit(x,y,w,h,action,arg)
    table.insert(hitboxes,{
        x1=math.floor(x),y1=math.floor(y),
        x2=math.floor(x+w-1),y2=math.floor(y+h-1),
        action=action,arg=arg,
    })
end

local function button(x,y,w,h,label,color,action,arg,active)
    fill(x,y,w,h,active and C.accent or color)
    frame(x,y,w,h,C.border)

    local scale = (h >= 16 and w >= textWidth(label,2)+8) and 2 or 1
    local tx=x+math.max(3,math.floor((w-textWidth(label,scale))/2))
    local ty=y+math.max(2,math.floor((h-5*scale)/2))
    text(tx,ty,label,C.white,scale)
    addHit(x,y,w,h,action,arg)
end

local function panel(x,y,w,h,title)
    fill(x,y,w,h,colors.black)
    frame(x,y,w,h,C.border)
    if title then text(x+5,y+4,title,C.accent,1) end
end

local function meter(x,y,w,h,value,color)
    value=math.max(0,math.min(100,tonumber(value) or 0))
    fill(x,y,w,h,colors.gray)
    local fw=math.floor(w*value/100)
    if fw>0 then fill(x,y,fw,h,color) end
    frame(x,y,w,h,C.border)
end

local function fmt(v,d)
    v=tonumber(v)
    if not v then return "-" end
    return string.format("%."..tostring(d or 1).."f",v)
end

local function statusColor(status)
    if status=="RUNNING" or status=="ONLINE" then return C.good end
    if status=="STARTING" or status=="DEGRADED" then return C.warn end
    return C.bad
end


local function updateHandDisplay(data,masterAlive,collectorFresh,pending,nodes)
    -- CC:Tweaked's in-hand Pocket renderer always draws the text terminal.
    -- CC:Graphics only replaces the opened GUI. Keep a compact text buffer
    -- current, then switch straight back to graphics mode for the opened UI.
    local status=data and data.plant and data.plant.status or "NO DATA"
    local rpm=data and data.power and data.power.rpm or 0
    local load=data and data.power and data.power.load or 0
    local battery=data and data.battery and data.battery.percent or 0
    local armed=data and data.control and data.control.armed or false
    local link=not masterAlive and "MASTER LOST"
        or not collectorFresh and "DATA STALE"
        or pending and "CMD WAIT"
        or "LINK OK"
    local nodeCount=#(nodes or {})

    local signature=table.concat({
        tostring(status),
        string.format("%.1f",rpm or 0),
        string.format("%.0f",load or 0),
        string.format("%.0f",battery or 0),
        tostring(armed),
        link,
        tostring(nodeCount),
    },"|")

    if signature==handSignature then return end
    handSignature=signature

    local ok=pcall(function()
        term.setGraphicsMode(false)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.clear()

        local tw,th=term.getSize()
        local function line(y,value,color)
            if y>th then return end
            value=tostring(value or "")
            if #value>tw then value=value:sub(1,tw) end
            term.setCursorPos(math.max(1,math.floor((tw-#value)/2)+1),y)
            term.setTextColor(color or colors.white)
            term.write(value)
        end

        line(2,"INFRA POCKET",colors.yellow)
        line(4,status,statusColor(status))
        line(6,string.format("RPM %.1f",rpm or 0),colors.white)
        line(7,string.format("LOAD %.0f%%",load or 0),colors.lightGray)
        line(9,string.format("BAT %.0f%%",battery or 0),
            (battery or 0)<20 and colors.red or colors.lime)
        line(11,armed and "AUTO ARMED" or "AUTO DISARMED",
            armed and colors.lime or colors.orange)
        line(13,link,
            link=="LINK OK" and colors.lime or colors.orange)
        line(15,"NODES "..tostring(nodeCount),colors.cyan)

        term.setGraphicsMode(graphicsMode)
    end)

    if not ok then
        pcall(term.setGraphicsMode,graphicsMode)
    end
end

local function header(page,data,masterAlive,collectorFresh,pending)
    fill(0,0,pw,16,C.panel)
    text(5,5,"INFRA POCKET",C.yellow,1)

    local status=data and data.plant and data.plant.status or "NO DATA"
    local col=pending and C.warn or (not masterAlive and C.bad or (collectorFresh and statusColor(status) or C.warn))
    fill(pw-13,3,9,9,col)
end

local function nav(page)
    local labels={"HOME","CTRL","MOTOR","EVENT","SYS"}
    local gap=2
    local y=ph-18
    local bw=math.floor((pw-gap*(#labels+1))/#labels)

    fill(0,y,pw,18,C.panel)
    for i,label in ipairs(labels) do
        local x=gap+(i-1)*(bw+gap)
        button(x,y+2,bw,14,label,C.blue,"page",i,page==i)
    end
end

local function statusPage(data,collectorFresh)
    local x=4
    local y=21
    local w=pw-8
    local h=ph-y-23
    panel(x,y,w,h,"STEAM PLANT")

    if not data then
        text(x+8,y+24,"WAITING TELEMETRY",C.warn,1)
        return
    end

    local status=data.plant and data.plant.status or "-"
    fill(x+5,y+17,w-10,18,statusColor(status))
    text(x+9,y+23,status,C.white,1)

    local cardY=y+41
    local gap=4
    local cardW=math.floor((w-gap*4)/3)

    local function metric(cx,label,value,color)
        fill(cx,cardY,cardW,29,colors.black)
        frame(cx,cardY,cardW,29,color)
        text(cx+4,cardY+4,label,color,1)
        text(cx+4,cardY+15,value,C.white,1)
    end

    metric(x+gap,"RPM",fmt(data.power.rpm,1),C.yellow)
    metric(x+gap*2+cardW,"LOAD",fmt(data.power.load,1).."%",C.warn)
    metric(x+gap*3+cardW*2,"BAT",fmt(data.battery.percent,0).."%",C.good)

    local my=cardY+37
    text(x+6,my,"WATER",C.accent,1)
    meter(x+48,my-1,w-57,7,data.boiler.water,colors.blue)
    text(x+6,my+15,"HEAT",C.accent,1)
    meter(x+48,my+14,w-57,7,data.boiler.heat,colors.red)

    text(x+6,my+31,"STATE "..tostring(data.control.state),C.muted,1)
    text(x+6,my+42,"AUTO "..(data.control.armed and "ARMED" or "DISARMED"),
        data.control.armed and C.good or C.bad,1)

    if not collectorFresh then
        text(x+6,h+y-12,"TELEMETRY STALE",C.bad,1)
    end
end

local function controlPage(data)
    local x=4
    local y=21
    local w=pw-8
    local h=ph-y-23
    panel(x,y,w,h,"CONTROL BUS")

    if not data then
        text(x+8,y+24,"NO DATA",C.bad,1)
        return
    end

    local by=y+20
    local bw=w-12
    button(x+6,by,bw,17,"AUTO START",C.good,"command",{command="procedure"})
    button(x+6,by+21,bw,17,"ABORT",C.bad,"command",{command="abort"})
    button(x+6,by+42,bw,17,data.control.armed and "DISARM" or "ARM",
        data.control.armed and C.warn or C.good,
        "command",{command=data.control.armed and "disarm" or "arm"})

    local cy=by+68
    local gap=4
    local cw=math.floor((bw-gap*2)/3)

    button(x+6,cy,cw,18,"MAIN",data.control.mainClutchEngaged and C.good or C.bad,
        "command",{command=data.control.mainClutchEngaged and "main_off" or "main_on"})
    button(x+6+cw+gap,cy,cw,18,"GEN",data.control.genClutchEngaged and C.good or C.bad,
        "command",{command=data.control.genClutchEngaged and "gen_off" or "gen_on"})
    button(x+6+(cw+gap)*2,cy,cw,18,"ALT",data.control.alternatorClutchEngaged and C.good or C.bad,
        "command",{command=data.control.alternatorClutchEngaged and "alt_off" or "alt_on"})
end

local function motorPage(data)
    local x=4
    local y=21
    local w=pw-8
    local h=ph-y-23
    panel(x,y,w,h,"MOTOR")

    if not data then
        text(x+8,y+24,"NO DATA",C.bad,1)
        return
    end

    text(x+8,y+20,"RPM "..fmt(data.motor.rpm,1),C.white,2)
    text(x+8,y+37,"DRAW "..fmt(data.motor.consumption,0).." FE/T",C.muted,1)

    local gap=5
    local bw=math.floor((w-17)/2)
    local by=y+54

    button(x+6,by,bw,18,"32 RPM",C.blue,"command",{command="motor_speed",rpm=32})
    button(x+11+bw,by,bw,18,"64 RPM",C.blue,"command",{command="motor_speed",rpm=64})
    button(x+6,by+23,bw,18,"128 RPM",C.accent,"command",{command="motor_speed",rpm=128})
    button(x+11+bw,by+23,bw,18,"STOP",C.bad,"command",{command="motor_stop"})
    button(x+6,by+51,w-12,17,"RUN TOPOLOGY",C.blue,"command",{command="running_topology"})
    button(x+6,by+72,w-12,17,"ALL CUT",C.warn,"command",{command="all_cut"})
end

local function eventsPage(events)
    local x=4
    local y=21
    local w=pw-8
    local h=ph-y-23
    panel(x,y,w,h,"EVENT BUS")

    local row=y+19
    local maxRows=math.max(0,math.floor((h-23)/12))

    if #(events or {})==0 then
        text(x+7,row,"NO EVENTS",C.muted,1)
        return
    end

    for i=1,math.min(#events,maxRows) do
        local e=events[i]
        local col=e.level=="critical" and C.bad
            or e.level=="warning" and C.warn
            or e.level=="success" and C.good
            or C.accent
        text(x+7,row,tostring(e.code or "EVENT"),col,1)
        row=row+12
    end
end

local function systemPage(nodes,selected,confirming)
    local x=4
    local y=21
    local w=pw-8
    local h=ph-y-23
    panel(x,y,w,h,"MACHINES")

    local list=nodes or {}
    local row=y+18
    local rowH=20
    local maxRows=math.max(0,math.floor((h-49)/rowH))

    if #list==0 then
        text(x+7,row,"NO NODES",C.warn,1)
    end

    for i=1,math.min(#list,maxRows) do
        local node=list[i]
        local on=selected and selected[node.key]
        fill(x+5,row,w-10,rowH-3,on and C.blue or colors.black)
        frame(x+5,row,w-10,rowH-3,node.localNode and C.accent or C.border)
        text(x+10,row+5,(on and "[X] " or "[ ] ")..tostring(node.label or node.key),
            node.localNode and C.accent or C.white,1)
        addHit(x+5,row,w-10,rowH-3,"node_toggle",node.key)
        row=row+rowH
    end

    button(x+6,y+h-24,w-12,17,
        confirming and "CONFIRM REBOOT" or "REBOOT SELECTED",
        confirming and C.bad or C.warn,
        "node_reboot_selected")
end

function M.init(requestedMode)
    if type(term.setGraphicsMode)~="function"
        or type(term.drawPixels)~="function"
        or type(term.setPixel)~="function"
    then
        error("CC:Graphics unavailable on pocket terminal")
    end

    graphicsMode=requestedMode or 1
    term.setGraphicsMode(graphicsMode)
    local ok,w,h=pcall(term.getSize,graphicsMode)
    if ok and tonumber(w) and tonumber(h) then
        pw,ph=w,h
    else
        local tw,th=term.getSize()
        pw,ph=tw*6,th*9
    end
end

function M.draw(page,data,events,masterAlive,collectorFresh,pending,toast,toastColor,nodes,selected,confirming)
    hitboxes={}
    updateHandDisplay(data,masterAlive,collectorFresh,pending,nodes)

    local frozen=type(term.setFrozen)=="function"
    if frozen then pcall(term.setFrozen,true) end

    fill(0,0,pw,ph,C.bg)
    header(page,data,masterAlive,collectorFresh,pending)

    if page==1 then statusPage(data,collectorFresh)
    elseif page==2 then controlPage(data)
    elseif page==3 then motorPage(data)
    elseif page==4 then eventsPage(events or {})
    else systemPage(nodes or {},selected or {},confirming)
    end

    if toast then
        local tw=math.min(pw-8,textWidth(toast,1)+10)
        fill(4,ph-39,tw,13,colors.black)
        frame(4,ph-39,tw,13,toastColor or C.white)
        text(8,ph-35,tostring(toast),toastColor or C.white,1)
    end

    nav(page)

    if frozen then pcall(term.setFrozen,false) end
end

function M.click(page,data,x,y,nodes,selected)
    for _,h in ipairs(hitboxes) do
        if x>=h.x1 and x<=h.x2 and y>=h.y1 and y<=h.y2 then
            return h.action,h.arg
        end
    end
    return nil
end

return M
