local M = {}

local hitboxes = {}
local mode = 1
local pw, ph, textW, textH = 0, 0, 0, 0

local history = {}
local lastSampleTimestamp = nil
local MAX_HISTORY = 120

local C = {
    bg = colors.black,
    panel = colors.gray,
    panelDark = colors.black,
    border = colors.lightGray,
    good = colors.lime,
    warn = colors.orange,
    bad = colors.red,
    accent = colors.cyan,
    blue = colors.blue,
    water = colors.blue,
    heat = colors.red,
    brass = colors.yellow,
    white = colors.white,
    muted = colors.lightGray,
    purple = colors.purple,
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
    ["_"]={"000","000","000","000","111"}, ["+"]={"000","010","111","010","000"},
}

local function fill(mon,x,y,w,h,color)
    if w <= 0 or h <= 0 then return end
    mon.drawPixels(math.floor(x), math.floor(y), color, math.floor(w), math.floor(h))
end

local function frame(mon,x,y,w,h,color)
    fill(mon,x,y,w,1,color)
    fill(mon,x,y+h-1,w,1,color)
    fill(mon,x,y,1,h,color)
    fill(mon,x+w-1,y,1,h,color)
end

local function textWidth(value, scale)
    return #tostring(value or "") * 4 * (scale or 1)
end

local function text(mon,x,y,value,color,scale)
    value = tostring(value or ""):upper()
    scale = scale or 1
    local cursor = x

    for i = 1, #value do
        local glyph = FONT[value:sub(i,i)] or {"111","101","101","101","111"}
        for gy = 1, 5 do
            for gx = 1, 3 do
                if glyph[gy]:sub(gx,gx) == "1" then
                    fill(mon,
                        cursor + (gx - 1) * scale,
                        y + (gy - 1) * scale,
                        scale, scale, color)
                end
            end
        end
        cursor = cursor + 4 * scale
    end

    return cursor
end

local function line(mon,x0,y0,x1,y1,color)
    x0=math.floor(x0); y0=math.floor(y0); x1=math.floor(x1); y1=math.floor(y1)
    local dx=math.abs(x1-x0)
    local sx=x0<x1 and 1 or -1
    local dy=-math.abs(y1-y0)
    local sy=y0<y1 and 1 or -1
    local err=dx+dy

    while true do
        mon.setPixel(x0,y0,color)
        if x0==x1 and y0==y1 then break end
        local e2=2*err
        if e2>=dy then err=err+dy; x0=x0+sx end
        if e2<=dx then err=err+dx; y0=y0+sy end
    end
end

local function addHitPx(x,y,w,h,action,arg)
    table.insert(hitboxes,{
        x1=math.floor(x), y1=math.floor(y),
        x2=math.floor(x+w-1), y2=math.floor(y+h-1),
        action=action, arg=arg
    })
end

local function panel(mon,x,y,w,h,title)
    fill(mon,x,y,w,h,C.panelDark)
    frame(mon,x,y,w,h,C.border)
    if title then
        text(mon,x+5,y+4,title,C.accent,1)
    end
end

local function button(mon,x,y,w,h,label,color,action,arg,active)
    fill(mon,x,y,w,h,active and C.accent or color)
    frame(mon,x,y,w,h,active and C.white or C.border)

    local tw = textWidth(label,1)
    local tx = x + math.max(3,math.floor((w-tw)/2))
    local ty = y + math.max(2,math.floor((h-5)/2))
    text(mon,tx,ty,label,C.white,1)
    addHitPx(x,y,w,h,action,arg)
end

local function statusColor(status)
    if status=="RUNNING" or status=="ONLINE" then return C.good end
    if status=="STARTING" or status=="DEGRADED" then return C.warn end
    return C.bad
end

local function meter(mon,x,y,w,h,value,color)
    value=math.max(0,math.min(100,tonumber(value) or 0))
    fill(mon,x,y,w,h,colors.gray)
    local fw=math.floor(w*value/100)
    if fw>0 then fill(mon,x,y,fw,h,color) end
    frame(mon,x,y,w,h,C.border)
end

local function fmt(v,d)
    v=tonumber(v)
    if not v then return "-" end
    return string.format("%."..tostring(d or 1).."f",v)
end

local function sample(data)
    if not data or not data.timestamp or data.timestamp == lastSampleTimestamp then return end
    lastSampleTimestamp = data.timestamp

    table.insert(history,{
        timestamp=data.timestamp,
        rpm=math.abs(tonumber(data.power and data.power.rpm) or 0),
        load=tonumber(data.power and data.power.load) or 0,
        battery=tonumber(data.battery and data.battery.percent) or 0,
        water=tonumber(data.boiler and data.boiler.water) or 0,
        heat=tonumber(data.boiler and data.boiler.heat) or 0,
    })

    while #history > MAX_HISTORY do table.remove(history,1) end
end

local function graph(mon,x,y,w,h,title,key,color,minValue,maxValue)
    panel(mon,x,y,w,h,title)

    local gx=x+6
    local gy=y+17
    local gw=w-12
    local gh=h-23

    fill(mon,gx,gy,gw,gh,colors.black)

    for i=1,3 do
        local yy=gy+math.floor((gh-1)*i/4)
        fill(mon,gx,yy,gw,1,colors.gray)
    end

    if #history < 2 then
        text(mon,gx+5,gy+math.floor(gh/2)-2,"WAITING FOR HISTORY",C.muted,1)
        return
    end

    local lo=minValue
    local hi=maxValue

    if hi == nil then
        hi=0
        for _,s in ipairs(history) do
            hi=math.max(hi,tonumber(s[key]) or 0)
        end
        hi=math.max(hi,1)
    end

    if lo == nil then lo=0 end
    if hi <= lo then hi=lo+1 end

    local prevX,prevY=nil,nil
    for i,s in ipairs(history) do
        local value=tonumber(s[key]) or 0
        local nx=(i-1)/math.max(1,#history-1)
        local nv=(value-lo)/(hi-lo)
        nv=math.max(0,math.min(1,nv))

        local px=gx+math.floor(nx*(gw-1))
        local py=gy+gh-1-math.floor(nv*(gh-1))

        if prevX then line(mon,prevX,prevY,px,py,color) end
        prevX,prevY=px,py
    end

    local latest=history[#history][key] or 0
    text(mon,gx+3,gy+3,fmt(latest,1),C.white,1)
end

local function compactLayout()
    return ph < 150 or (ph > 0 and (pw / ph) >= 2.20)
end

local function fitText(value,maxPixels)
    value=tostring(value or "")
    if textWidth(value,1)<=maxPixels then return value end
    local chars=math.max(1,math.floor(maxPixels/4)-1)
    if chars<=1 then return value:sub(1,chars) end
    return value:sub(1,chars-1).."."
end

local function drawHeader(mon,page,data,collectorFresh)
    local compact=compactLayout()
    local hh=compact and 14 or 18
    fill(mon,0,0,pw,hh,C.panel)

    local title=compact and "LOCAL COLLECTOR" or "LOCAL COLLECTOR CONTROL"
    text(mon,5,compact and 4 or 6,title,C.brass,1)

    local status=data and data.plant and data.plant.status or "NO DATA"
    local statusW=math.max(38,textWidth(status,1)+10)
    local sy=compact and 2 or 3
    local sh=compact and 10 or 12
    fill(mon,pw-statusW-4,sy,statusW,sh,statusColor(status))
    text(mon,pw-statusW+1,compact and 5 or 7,status,C.white,1)

    local link=collectorFresh and "LINK" or "STALE"
    local linkW=textWidth(link,1)
    local lx=pw-statusW-linkW-12
    if lx > textWidth(title,1)+14 then
        text(mon,lx,compact and 5 or 7,link,collectorFresh and C.good or C.bad,1)
    end
end

local function drawNav(mon,page)
    local compact=compactLayout()
    local navH=compact and 17 or 20
    local navY=ph-navH
    fill(mon,0,navY,pw,navH,C.panel)

    local labels={
        {"HOME","dashboard"},
        {"GRAPHS","graphs"},
        {"EVENTS","events"},
        {"MACH","machines"},
        {"DEBUG","debug"},
    }

    local gap=compact and 2 or 3
    local bw=math.floor((pw-gap*(#labels+1))/#labels)
    local bh=compact and 12 or 14
    local by=navY+math.floor((navH-bh)/2)

    for i,item in ipairs(labels) do
        local x=gap+(i-1)*(bw+gap)
        button(mon,x,by,bw,bh,fitText(item[1],bw-6),C.blue,"page",item[2],page==item[2])
    end
end

local function drawCompactDashboard(mon,data,collectorFresh,pending)
    local headerH=14
    local navH=17
    local gap=4
    local y=headerH+4
    local h=ph-y-navH-4
    local x=4
    local totalW=pw-8

    -- Keep controls narrow but always usable on panoramic 1xN monitors.
    local railW=math.max(104,math.min(150,math.floor(totalW*0.32)))
    local mainW=totalW-railW-gap
    local rx=x+mainW+gap

    panel(mon,x,y,mainW,h,"PLANT")
    panel(mon,rx,y,railW,h,"CONTROL")

    if not data then
        text(mon,x+7,y+20,"WAITING TELEMETRY",C.warn,1)
        return
    end

    -- Metrics: one shallow row.
    local innerX=x+5
    local innerW=mainW-10
    local cardGap=4
    local cardW=math.floor((innerW-cardGap*2)/3)
    local cardY=y+16
    local cardH=25

    local function compactMetric(cx,label,value,color)
        fill(mon,cx,cardY,cardW,cardH,colors.black)
        frame(mon,cx,cardY,cardW,cardH,color)
        text(mon,cx+4,cardY+4,label,color,1)
        text(mon,cx+4,cardY+14,fitText(value,cardW-8),C.white,1)
    end

    compactMetric(innerX,"RPM",fmt(data.power.rpm,1),C.brass)
    compactMetric(innerX+cardW+cardGap,"LOAD",fmt(data.power.load,1).."%",C.warn)
    compactMetric(innerX+(cardW+cardGap)*2,"BAT",fmt(data.battery.percent,1).."%",C.good)

    -- Use the remaining height fluidly instead of assuming a tall monitor.
    local infoY=cardY+cardH+5
    local bottomY=y+h-5
    local remaining=bottomY-infoY

    if remaining >= 28 then
        local labelW=34
        text(mon,innerX,infoY+1,"WATER",C.accent,1)
        meter(mon,innerX+labelW,infoY,innerW-labelW,7,data.boiler.water,C.water)

        text(mon,innerX,infoY+12,"HEAT",C.accent,1)
        meter(mon,innerX+labelW,infoY+11,innerW-labelW,7,data.boiler.heat,C.heat)

        local stateY=infoY+23
        if stateY+5 < bottomY then
            local state="STATE "..tostring(data.control.state)
            local auto=data.control.armed and "AUTO ARMED" or "AUTO DISARMED"
            text(mon,innerX,stateY,fitText(state,math.floor(innerW*0.58)),C.muted,1)
            local autoW=textWidth(auto,1)
            text(mon,x+mainW-autoW-7,stateY,auto,data.control.armed and C.good or C.bad,1)
        end
    elseif remaining >= 14 then
        text(mon,innerX,infoY,
            "W "..fmt(data.boiler.water,0).."%  H "..fmt(data.boiler.heat,0).."%  "
            ..(data.control.armed and "AUTO ON" or "AUTO OFF"),
            data.control.armed and C.good or C.muted,1)
    end

    -- Control area becomes a responsive 2-column grid.
    local bx=rx+5
    local bw=railW-10
    local colGap=4
    local colW=math.floor((bw-colGap)/2)
    local by=y+17
    local usable=h-22
    local rows=3
    local rowGap=4
    local bh=math.max(11,math.floor((usable-rowGap*(rows-1))/rows))
    bh=math.min(bh,20)

    button(mon,bx,by,colW,bh,"START",C.good,"command","procedure")
    button(mon,bx+colW+colGap,by,colW,bh,"ABORT",C.bad,"command","abort")

    button(mon,bx,by+bh+rowGap,colW,bh,
        data.control.armed and "DISARM" or "ARM",
        data.control.armed and C.warn or C.good,
        "command",data.control.armed and "disarm" or "arm")
    button(mon,bx+colW+colGap,by+bh+rowGap,colW,bh,
        data.control.mainClutchEngaged and "MAIN ON" or "MAIN CUT",
        data.control.mainClutchEngaged and C.good or C.bad,
        "command",data.control.mainClutchEngaged and "main_off" or "main_on")

    button(mon,bx,by+(bh+rowGap)*2,colW,bh,
        data.control.genClutchEngaged and "GEN ON" or "GEN CUT",
        data.control.genClutchEngaged and C.good or C.bad,
        "command",data.control.genClutchEngaged and "gen_off" or "gen_on")
    button(mon,bx+colW+colGap,by+(bh+rowGap)*2,colW,bh,
        data.control.alternatorClutchEngaged and "ALT ON" or "ALT CUT",
        data.control.alternatorClutchEngaged and C.good or C.bad,
        "command",data.control.alternatorClutchEngaged and "alt_off" or "alt_on")

    if pending then
        text(mon,rx+7,y+h-9,"CMD WAIT",C.warn,1)
    elseif not collectorFresh then
        text(mon,rx+7,y+h-9,"STALE",C.bad,1)
    end
end

local function drawDashboard(mon,data,collectorFresh,pending)
    if compactLayout() then
        drawCompactDashboard(mon,data,collectorFresh,pending)
        return
    end

    local contentY=23
    local contentH=ph-contentY-25
    local railW=math.max(98,math.floor(pw*0.33))
    local gap=6
    local mainW=pw-railW-gap*3
    local x=gap
    local rx=x+mainW+gap

    panel(mon,x,contentY,mainW,contentH,"PLANT OVERVIEW")
    panel(mon,rx,contentY,railW,contentH,"CONTROL BUS")

    if not data then
        text(mon,x+8,contentY+28,"WAITING FOR TELEMETRY",C.warn,1)
        return
    end

    local cardGap=5
    local cardW=math.floor((mainW-cardGap*4)/3)
    local cardY=contentY+19
    local cardH=34

    local function metricCard(cx,label,value,color)
        fill(mon,cx,cardY,cardW,cardH,colors.black)
        frame(mon,cx,cardY,cardW,cardH,color)
        text(mon,cx+5,cardY+5,label,color,1)
        text(mon,cx+5,cardY+17,value,C.white,2)
    end

    metricCard(x+cardGap,"RPM",fmt(data.power.rpm,1),C.brass)
    metricCard(x+cardGap*2+cardW,"LOAD",fmt(data.power.load,1).."%",C.warn)
    metricCard(x+cardGap*3+cardW*2,"BAT",fmt(data.battery.percent,1).."%",C.good)

    local meterY=cardY+cardH+12
    text(mon,x+8,meterY,"WATER",C.accent,1)
    meter(mon,x+54,meterY-1,mainW-64,8,data.boiler.water,C.water)

    text(mon,x+8,meterY+17,"HEAT",C.accent,1)
    meter(mon,x+54,meterY+16,mainW-64,8,data.boiler.heat,C.heat)

    text(mon,x+8,meterY+34,"BATTERY",C.accent,1)
    meter(mon,x+64,meterY+33,mainW-74,8,data.battery.percent,
        (data.battery.percent or 0)<20 and C.bad or C.good)

    local clutchY=meterY+53
    text(mon,x+8,clutchY,"CLUTCHES",C.accent,1)

    local cw=math.floor((mainW-32)/3)
    local function clutch(cx,label,on)
        fill(mon,cx,clutchY+10,cw,16,on and C.good or C.bad)
        frame(mon,cx,clutchY+10,cw,16,C.border)
        text(mon,cx+5,clutchY+16,label.." "..(on and "ON" or "CUT"),C.white,1)
    end

    clutch(x+8,"MAIN",data.control.mainClutchEngaged)
    clutch(x+16+cw,"GEN",data.control.genClutchEngaged)
    clutch(x+24+cw*2,"ALT",data.control.alternatorClutchEngaged)

    local stateY=clutchY+34
    text(mon,x+8,stateY,"STATE "..tostring(data.control.state),C.muted,1)
    text(mon,x+8,stateY+10,"AUTO "..(data.control.armed and "ARMED" or "DISARMED"),
        data.control.armed and C.good or C.bad,1)

    local bw=railW-12
    local by=contentY+21
    button(mon,rx+6,by,bw,15,"AUTO START",C.good,"command","procedure")
    button(mon,rx+6,by+19,bw,15,"ABORT",C.bad,"command","abort")
    button(mon,rx+6,by+38,bw,15,data.control.armed and "DISARM" or "ARM",
        data.control.armed and C.warn or C.good,
        "command",data.control.armed and "disarm" or "arm")

    local smallW=math.floor((bw-8)/3)
    local clutchButtonY=by+61
    button(mon,rx+6,clutchButtonY,smallW,15,"MAIN",
        data.control.mainClutchEngaged and C.good or C.bad,
        "command",data.control.mainClutchEngaged and "main_off" or "main_on")
    button(mon,rx+10+smallW,clutchButtonY,smallW,15,"GEN",
        data.control.genClutchEngaged and C.good or C.bad,
        "command",data.control.genClutchEngaged and "gen_off" or "gen_on")
    button(mon,rx+14+smallW*2,clutchButtonY,smallW,15,"ALT",
        data.control.alternatorClutchEngaged and C.good or C.bad,
        "command",data.control.alternatorClutchEngaged and "alt_off" or "alt_on")

    button(mon,rx+6,clutchButtonY+21,bw,15,"MOTOR STOP",C.bad,"command","motor_stop")
    button(mon,rx+6,clutchButtonY+40,bw,15,"RUN TOPOLOGY",C.blue,"command","running_topology")

    text(mon,rx+8,contentY+contentH-16,
        collectorFresh and "LOCAL OK" or "LOCAL LOST",
        collectorFresh and C.good or C.bad,1)

    if pending then
        text(mon,rx+8,contentY+contentH-28,"CMD WAIT ACK",C.warn,1)
    end
end

local function drawGraphs(mon)
    local contentY=23
    local bottom=ph-25
    local gap=6
    local fullH=bottom-contentY
    local topH=math.floor((fullH-gap)/2)
    local bottomH=fullH-topH-gap
    local halfW=math.floor((pw-gap*3)/2)

    graph(mon,gap,contentY,halfW,topH,"RPM HISTORY","rpm",C.brass,0,nil)
    graph(mon,gap*2+halfW,contentY,halfW,topH,"LOAD HISTORY","load",C.warn,0,100)
    graph(mon,gap,contentY+topH+gap,halfW,bottomH,"BATTERY","battery",C.good,0,100)

    panel(mon,gap*2+halfW,contentY+topH+gap,halfW,bottomH,"BOILER")
    local gx=gap*2+halfW+7
    local gy=contentY+topH+gap+19
    local gw=halfW-14
    local gh=bottomH-25

    fill(mon,gx,gy,gw,gh,colors.black)

    if #history >= 2 then
        local function drawSeries(key,color)
            local px0,py0=nil,nil
            for i,s in ipairs(history) do
                local nx=(i-1)/math.max(1,#history-1)
                local nv=math.max(0,math.min(100,tonumber(s[key]) or 0))/100
                local px=gx+math.floor(nx*(gw-1))
                local py=gy+gh-1-math.floor(nv*(gh-1))
                if px0 then line(mon,px0,py0,px,py,color) end
                px0,py0=px,py
            end
        end
        drawSeries("water",C.water)
        drawSeries("heat",C.heat)
    end

    text(mon,gx+3,gy+3,"WATER",C.water,1)
    text(mon,gx+48,gy+3,"HEAT",C.heat,1)
end

local function eventColor(level)
    if level=="critical" then return C.bad end
    if level=="warning" then return C.warn end
    if level=="success" then return C.good end
    return C.accent
end

local function drawEvents(mon,events)
    local x=6
    local y=23
    local w=pw-12
    local h=ph-y-25
    panel(mon,x,y,w,h,"EVENT BUS")

    local rowY=y+18
    local maxRows=math.max(0,math.floor((h-22)/10))

    for i=1,math.min(#(events or {}),maxRows) do
        local e=events[i]
        local code=tostring(e.code or "EVENT")
        local msg=tostring(e.message or "")
        local col=eventColor(e.level)

        text(mon,x+6,rowY,code,col,1)
        local mx=x+6+math.min(90,textWidth(code,1)+10)
        text(mon,mx,rowY,msg,C.muted,1)
        rowY=rowY+10
    end
end


local function drawMachines(mon,nodes)
    local x=6
    local y=23
    local w=pw-12
    local h=ph-y-25
    panel(mon,x,y,w,h,"MACHINE NETWORK")

    local rowY=y+21
    local rowH=24
    local rebootW=72
    local list=nodes or {}

    if #list == 0 then
        text(mon,x+8,rowY,"NO NODES DISCOVERED",C.warn,1)
        return
    end

    for i,node in ipairs(list) do
        if rowY+rowH > y+h-4 then break end

        fill(mon,x+6,rowY,w-12,rowH-3,colors.black)
        local rowColor = node.conflict and C.bad or (node.localNode and C.accent or C.border)
        frame(mon,x+6,rowY,w-12,rowH-3,rowColor)

        text(mon,x+12,rowY+5,tostring(node.label or node.key),node.conflict and C.bad or (node.localNode and C.accent or C.white),1)
        text(mon,x+12,rowY+14,node.conflict and "IDENTITY CONFLICT" or tostring(node.key),node.conflict and C.bad or C.muted,1)

        button(mon,x+w-rebootW-12,rowY+3,rebootW,15,"REBOOT",C.bad,"node_reboot",node.key)
        rowY=rowY+rowH
    end
end

local function drawDebug(mon,data,collectorFresh,events,pending,debugInfo)
    local x=6
    local y=23
    local gap=6
    local w=pw-12
    local h=ph-y-25
    local leftW=math.floor((w-gap)/2)
    local rightW=w-leftW-gap

    panel(mon,x,y,leftW,h,"SYSTEM")
    panel(mon,x+leftW+gap,y,rightW,h,"RECENT EVENTS")

    local lx=x+7
    local ly=y+20

    text(mon,lx,ly,"BACKEND CCGRAPHICS",C.good,1)
    text(mon,lx,ly+12,"COLLECTOR "..(collectorFresh and "OK" or "STALE"),
        collectorFresh and C.good or C.bad,1)

    if debugInfo then
        text(mon,lx,ly+24,"TELEMETRY AGE "..fmt((debugInfo.telemetryAgeMs or 0)/1000,1).."S",C.white,1)
    end

    if data then
        text(mon,lx,ly+36,"STATE "..tostring(data.control.state),C.white,1)
        text(mon,lx,ly+48,"RPM "..fmt(data.power.rpm,2),C.white,1)
        text(mon,lx,ly+60,"CAP "..fmt(data.power.capacity,0),C.white,1)
        text(mon,lx,ly+72,"STRESS "..fmt(data.power.stress,0),C.white,1)
        text(mon,lx,ly+84,"MOTOR "..fmt(data.motor.rpm,1),C.white,1)
        text(mon,lx,ly+96,
            "M "..(data.control.mainClutchEngaged and "ON" or "CUT")
            .." G "..(data.control.genClutchEngaged and "ON" or "CUT")
            .." A "..(data.control.alternatorClutchEngaged and "ON" or "CUT"),
            C.muted,1)
    end

    if pending then
        text(mon,lx,ly+112,"PENDING "..tostring(pending.command),C.warn,1)
    end

    local ex=x+leftW+gap+7
    local ey=y+20
    local maxRows=math.max(0,math.floor((h-25)/10))

    for i=1,math.min(#(events or {}),maxRows) do
        local e=events[i]
        text(mon,ex,ey,tostring(e.code or "EVENT"),eventColor(e.level),1)
        ey=ey+10
    end
end

function M.init(mon,requestedMode)
    if type(mon.setGraphicsMode)~="function"
        or type(mon.drawPixels)~="function"
        or type(mon.setPixel)~="function"
    then
        error("CC:Graphics API not available")
    end

    mode=requestedMode or 1
    mon.setGraphicsMode(mode)

    textW,textH=mon.getSize()
    local ok,w,h=pcall(mon.getSize,mode)

    if ok and tonumber(w) and tonumber(h) then
        pw,ph=w,h
    else
        pw,ph=textW*6,textH*9
    end

    if type(mon.setFrozen)=="function" then
        pcall(mon.setFrozen,false)
    end
end

function M.shutdown(mon)
    pcall(mon.setGraphicsMode,false)
end

function M.draw(mon,page,data,collectorFresh,latestEvent,events,pending,debugInfo)
    hitboxes={}
    sample(data)

    local frozen=type(mon.setFrozen)=="function"
    if frozen then pcall(mon.setFrozen,true) end

    fill(mon,0,0,pw,ph,C.bg)
    drawHeader(mon,page,data,collectorFresh)

    if page=="graphs" then
        drawGraphs(mon)
    elseif page=="events" then
        drawEvents(mon,events or {})
    elseif page=="machines" then
        drawMachines(mon,(debugInfo and debugInfo.nodes) or {})
    elseif page=="debug" then
        drawDebug(mon,data,collectorFresh,events or {},pending,debugInfo or {})
    else
        drawDashboard(mon,data,collectorFresh,pending)
    end

    drawNav(mon,page)

    if frozen then pcall(mon.setFrozen,false) end
end

function M.actionAt(x,y)
    for _,h in ipairs(hitboxes) do
        if x>=h.x1 and x<=h.x2 and y>=h.y1 and y<=h.y2 then
            return h.action,h.arg
        end
    end
    return nil
end

function M.getDebugGeometry()
    return {
        pixelWidth=pw,
        pixelHeight=ph,
        textWidth=textW,
        textHeight=textH,
        touchCoordinates="pixel-0-indexed",
        historySamples=#history,
        hitboxes=hitboxes,
    }
end

return M
