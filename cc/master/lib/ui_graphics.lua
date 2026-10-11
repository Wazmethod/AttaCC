local M = {}
local hitboxes = {}
local mode = 1
local pw, ph, textW, textH = 0, 0, 0, 0

local C = {
    bg = colors.black, panel = colors.gray, good = colors.lime,
    warn = colors.orange, bad = colors.red, accent = colors.cyan,
    white = colors.white, muted = colors.lightGray, yellow = colors.yellow,
    blue = colors.blue,
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
    ["_"]={"000","000","000","000","111"},
}

local function fill(mon,x,y,w,h,color)
    if w <= 0 or h <= 0 then return end
    mon.drawPixels(math.floor(x), math.floor(y), color, math.floor(w), math.floor(h))
end

local function frame(mon,x,y,w,h,color)
    fill(mon,x,y,w,1,color); fill(mon,x,y+h-1,w,1,color)
    fill(mon,x,y,1,h,color); fill(mon,x+w-1,y,1,h,color)
end

local function text(mon,x,y,value,color,scale)
    value=tostring(value or ""):upper(); scale=scale or 1
    local cursor=x
    for i=1,#value do
        local glyph=FONT[value:sub(i,i)] or {"111","101","101","101","111"}
        for gy=1,5 do
            for gx=1,3 do
                if glyph[gy]:sub(gx,gx)=="1" then
                    fill(mon,cursor+(gx-1)*scale,y+(gy-1)*scale,scale,scale,color)
                end
            end
        end
        cursor=cursor+4*scale
    end
end

local function addHitPx(x,y,w,h,action,arg)
    local sx=pw/math.max(1,textW); local sy=ph/math.max(1,textH)
    table.insert(hitboxes,{
        x1=math.floor(x/sx)+1, y1=math.floor(y/sy)+1,
        x2=math.ceil((x+w)/sx), y2=math.ceil((y+h)/sy),
        action=action,arg=arg
    })
end

local function button(mon,x,y,w,h,label,color,action,arg)
    fill(mon,x,y,w,h,color); frame(mon,x,y,w,h,C.white)
    text(mon,x+4,y+math.max(2,math.floor((h-5)/2)),label,C.white,1)
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
    frame(mon,x,y,w,h,C.white)
end

function M.init(mon,requestedMode)
    if type(mon.setGraphicsMode)~="function" or type(mon.drawPixels)~="function" then
        error("CC:Graphics API not available")
    end
    mode=requestedMode or 1
    mon.setGraphicsMode(mode)
    textW,textH=mon.getSize()
    local ok,w,h=pcall(mon.getSize,mode)
    if ok and tonumber(w) and tonumber(h) then pw,ph=w,h else pw,ph=textW*6,textH*9 end
    if type(mon.setFrozen)=="function" then pcall(mon.setFrozen,false) end
end

function M.shutdown(mon) pcall(mon.setGraphicsMode,false) end

function M.draw(mon,page,data,collectorFresh,latestEvent,events,pending,debugInfo)
    hitboxes={}
    local frozen=type(mon.setFrozen)=="function"
    if frozen then pcall(mon.setFrozen,true) end

    fill(mon,0,0,pw,ph,C.bg)
    fill(mon,0,0,pw,16,C.panel)
    text(mon,6,5,"STEAM PLANT",C.yellow,1)

    local status=data and data.plant and data.plant.status or "NO DATA"
    local sw=math.min(86,math.max(42,#status*5+12))
    fill(mon,pw-sw-4,3,sw,10,statusColor(status))
    text(mon,pw-sw+2,5,status,C.white,1)

    if page=="debug" then
        text(mon,6,24,"DEBUG",C.accent,2)
        text(mon,6,42,"BACKEND CCGRAPHICS",C.good,1)
        text(mon,6,54,"COLLECTOR "..(collectorFresh and "OK" or "STALE"),collectorFresh and C.good or C.bad,1)
        local y=72
        for i=1,math.min(#(events or {}),math.max(0,math.floor((ph-104)/9))) do
            local e=events[i]
            local col=e.level=="critical" and C.bad or e.level=="warning" and C.warn or e.level=="success" and C.good or C.accent
            text(mon,6,y,tostring(e.code or "EVENT"),col,1); y=y+9
        end
        button(mon,pw-82,ph-22,76,16,"DASHBOARD",C.blue,"page","dashboard")
        if frozen then pcall(mon.setFrozen,false) end
        return
    end

    local railW=math.max(92,math.floor(pw*0.30))
    local mainW=pw-railW-12
    text(mon,6,24,"KINETIC",C.accent,2)

    if not data then
        text(mon,6,46,"WAITING FOR TELEMETRY",C.warn,1)
    else
        text(mon,6,45,"RPM "..string.format("%.1f",data.power.rpm or 0),C.white,2)
        text(mon,6,62,"LOAD "..string.format("%.1f",data.power.load or 0).."%",C.white,1)
        text(mon,6,74,"STRESS "..string.format("%.0f",data.power.stress or 0),C.muted,1)
        text(mon,6,84,"CAP "..string.format("%.0f",data.power.capacity or 0),C.muted,1)

        text(mon,6,102,"WATER",C.accent,1)
        meter(mon,48,101,math.max(30,mainW-54),7,data.boiler.water,colors.blue)
        text(mon,6,116,"HEAT",C.accent,1)
        meter(mon,48,115,math.max(30,mainW-54),7,data.boiler.heat,colors.red)
        text(mon,6,132,"BATTERY",C.accent,1)
        meter(mon,62,131,math.max(30,mainW-68),8,data.battery.percent,(data.battery.percent or 0)<20 and C.bad or C.good)

        text(mon,6,150,"MAIN "..(data.control.mainClutchEngaged and "ON" or "CUT"),data.control.mainClutchEngaged and C.good or C.bad,1)
        text(mon,76,150,"GEN "..(data.control.genClutchEngaged and "ON" or "CUT"),data.control.genClutchEngaged and C.good or C.bad,1)
        text(mon,138,150,"ALT "..(data.control.alternatorClutchEngaged and "ON" or "CUT"),data.control.alternatorClutchEngaged and C.good or C.bad,1)
        text(mon,6,164,"CTRL "..tostring(data.control.state),C.muted,1)
        text(mon,6,175,"AUTO "..(data.control.armed and "ARMED" or "DISARMED"),data.control.armed and C.good or C.bad,1)
    end

    local rx=pw-railW+4
    text(mon,rx,24,"CONTROL",C.yellow,1)
    text(mon,rx,35,collectorFresh and "COLLECTOR OK" or "COLLECTOR LOST",collectorFresh and C.good or C.bad,1)

    if data then
        local bw=railW-12
        button(mon,rx,50,bw,14,"AUTO START",C.good,"command","procedure")
        button(mon,rx,68,bw,14,"ABORT",C.bad,"command","abort")
        button(mon,rx,86,bw,14,data.control.armed and "DISARM" or "ARM",data.control.armed and C.warn or C.good,"command",data.control.armed and "disarm" or "arm")
        button(mon,rx,110,bw,12,"MAIN",data.control.mainClutchEngaged and C.good or C.bad,"command",data.control.mainClutchEngaged and "main_off" or "main_on")
        button(mon,rx,126,bw,12,"GEN",data.control.genClutchEngaged and C.good or C.bad,"command",data.control.genClutchEngaged and "gen_off" or "gen_on")
        button(mon,rx,142,bw,12,"ALT",data.control.alternatorClutchEngaged and C.good or C.bad,"command",data.control.alternatorClutchEngaged and "alt_off" or "alt_on")
    end

    button(mon,pw-railW+4,ph-22,railW-12,16,"DEBUG",C.blue,"page","debug")
    if pending then text(mon,rx,ph-34,"CMD WAIT ACK",C.warn,1) end

    if frozen then pcall(mon.setFrozen,false) end
end

function M.actionAt(x,y)
    for _,h in ipairs(hitboxes) do
        if x>=h.x1 and x<=h.x2 and y>=h.y1 and y<=h.y2 then return h.action,h.arg end
    end
    return nil
end

return M
