local config = require("lib.config")

local M = {}
local hitboxes = {}

local function resetHits() hitboxes = {} end
local function addHit(x1,y1,x2,y2,action,arg)
    table.insert(hitboxes,{x1=x1,y1=y1,x2=x2,y2=y2,action=action,arg=arg})
end

local function writeAt(mon,x,y,text,fg,bg)
    local w,h=mon.getSize()
    if y<1 or y>h or x>w then return end
    text=tostring(text or "")
    if x<1 then x=1 end
    if #text>(w-x+1) then text=text:sub(1,math.max(0,w-x+1)) end
    mon.setCursorPos(x,y)
    if bg then mon.setBackgroundColor(bg) end
    mon.setTextColor(fg or colors.white)
    mon.write(text)
    if bg then mon.setBackgroundColor(colors.black) end
end

local function writeClipped(mon,x,y,text,right,fg,bg)
    local maxWidth = math.max(0, (right or x) - x + 1)
    if maxWidth <= 0 then return end
    text = tostring(text or "")
    if #text > maxWidth then text = text:sub(1, maxWidth) end
    writeAt(mon,x,y,text,fg,bg)
end

local function fill(mon,x,y,width,bg)
    local w,h=mon.getSize()
    if y<1 or y>h or x>w or width<1 then return end
    width=math.min(width,w-x+1)
    mon.setCursorPos(x,y)
    mon.setBackgroundColor(bg)
    mon.write(string.rep(" ",width))
    mon.setBackgroundColor(colors.black)
end

local function centerIn(mon,x,y,width,text,fg,bg)
    fill(mon,x,y,width,bg)
    local tx=x+math.max(0,math.floor((width-#text)/2))
    writeAt(mon,tx,y,text,fg or colors.white,bg)
end

local function button(mon,x,y,width,label,bg,action,arg)
    centerIn(mon,x,y,width,label,colors.white,bg)
    addHit(x,y,x+width-1,y,action,arg)
end

local function bar(mon,x,y,width,value,fg)
    value=math.max(0,math.min(100,tonumber(value) or 0))
    local filled=math.floor(width*value/100+0.5)
    if filled>0 then fill(mon,x,y,filled,fg) end
    if width-filled>0 then fill(mon,x+filled,y,width-filled,colors.gray) end
end

local function statusColor(status)
    if status=="RUNNING" or status=="ONLINE" then return colors.green end
    if status=="STARTING" or status=="DEGRADED" then return colors.orange end
    return colors.red
end

local function levelColor(level)
    if level=="critical" then return colors.red end
    if level=="warning" then return colors.orange end
    if level=="success" then return colors.lime end
    return colors.lightBlue
end

local function fmtTime(ms)
    if not ms then return "--:--:--" end
    local sec=math.floor(ms/1000)
    return string.format("%02d:%02d:%02d",math.floor((sec/3600)%24),math.floor((sec/60)%60),sec%60)
end

local function tableAllows(filter,value)
    if type(filter)~="table" or next(filter)==nil then return true end
    return filter[value]==true
end

local function eventVisible(event)
    local filter=config.display and config.display.eventFilter or {}
    return tableAllows(filter.levels,event.level or "info")
        and tableAllows(filter.types,event.type or "")
        and tableAllows(filter.codes,event.code or "")
end

local PAGE_LABELS={control="CTRL",gen="GEN",data="DATA",logs="LOGS",debug="DEBUG"}

local function configuredPages()
    local pages=config.display and config.display.textPages
    if type(pages)~="table" or #pages==0 then return {"control"} end
    local out={}
    for _,p in ipairs(pages) do
        if PAGE_LABELS[p] then table.insert(out,p) end
    end
    if #out==0 then out={"control"} end
    return out
end

local function drawHeader(mon,page,data,machineLabel)
    local w=select(1,mon.getSize())
    fill(mon,1,1,w,colors.gray)

    local machineTitle=tostring(machineLabel or "STEAMPLANT")
    local maxTitle=math.max(8,math.floor(w*0.38))
    if #machineTitle>maxTitle then
        machineTitle=machineTitle:sub(1,math.max(1,maxTitle-1)).."."
    end
    writeAt(mon,2,1,machineTitle,colors.white,colors.gray)

    local centre="GRAPH MODE"
    local centreW=#centre+2
    local cx=math.max(2,math.floor((w-centreW)/2))
    if config.display and config.display.graphicsToggle then
        button(mon,cx,1,centreW,centre,colors.blue,"backend","ccgraphics")
    else
        writeAt(mon,cx+1,1,string.upper(page or "control"),colors.yellow,colors.gray)
    end

    if data then
        local status=data.plant and data.plant.status or "NO DATA"
        local statusText=" "..status.." "
        writeAt(mon,math.max(2,w-#statusText-1),1,statusText,colors.white,statusColor(status))
    end
end

local function drawSideNav(mon,page)
    local w,h=mon.getSize()
    local pages=configuredPages()
    local navW=math.min(11,math.max(8,math.floor(w*0.16)))
    local x=w-navW+1
    local y=3
    for _,p in ipairs(pages) do
        if y>h then break end
        local active=p==page
        button(mon,x,y,navW,PAGE_LABELS[p],active and colors.cyan or colors.blue,"page",p)
        y=y+2
    end
    return x-2
end

local function drawControl(mon,data,sourceFresh,pending)
    local w,h=mon.getSize()
    local mainRight=drawSideNav(mon,"control")
    if not data then
        writeAt(mon,2,4,"Waiting for telemetry...",colors.orange)
        return
    end

    local bw=math.max(10,math.floor((mainRight-5)/2))
    local bx1=2
    local bx2=bx1+bw+2
    local row=4

    button(mon,bx1,row,bw,"AUTO START",colors.green,"command","procedure")
    button(mon,bx2,row,bw,"GEN "..(data.control.genClutchEngaged and "ON" or "CUT"),
        data.control.genClutchEngaged and colors.green or colors.red,
        "command",data.control.genClutchEngaged and "gen_off" or "gen_on")

    row=row+2
    button(mon,bx1,row,bw,data.control.armed and "DISARM" or "ARM",
        data.control.armed and colors.orange or colors.green,
        "command",data.control.armed and "disarm" or "arm")
    button(mon,bx2,row,bw,"MAIN "..(data.control.mainClutchEngaged and "ON" or "CUT"),
        data.control.mainClutchEngaged and colors.green or colors.red,
        "command",data.control.mainClutchEngaged and "main_off" or "main_on")

    row=row+2
    button(mon,bx1,row,bw,"ABORT",colors.red,"command","abort")
    button(mon,bx2,row,bw,"ALT "..(data.control.alternatorClutchEngaged and "ON" or "CUT"),
        data.control.alternatorClutchEngaged and colors.green or colors.red,
        "command",data.control.alternatorClutchEngaged and "alt_off" or "alt_on")

    local sy=row+2
    if sy<=h then
        writeAt(mon,2,sy,"STATE "..tostring(data.control.state),colors.lightGray)
        writeAt(mon,2,sy+1,"LINK  "..(sourceFresh and "LOCAL OK" or "STALE"),sourceFresh and colors.lime or colors.red)
        writeAt(mon,2,sy+2,"AUTO  "..(data.control.armed and "ARMED" or "DISARMED"),data.control.armed and colors.lime or colors.red)
        if pending then writeAt(mon,2,sy+3,"CMD WAIT ACK",colors.orange) end
    end
end

local function drawGen(mon,data)
    local mainRight=drawSideNav(mon,"gen")
    local w,h=mon.getSize()
    if not data then
        writeAt(mon,2,4,"Waiting for telemetry...",colors.orange)
        return
    end

    local rpm=data.power and data.power.rpm or 0
    local raw=data.power and data.power.rawRpm or rpm
    local mult=data.power and data.power.rpmMultiplier or 1
    local motorRpm=data.motor and data.motor.rpm or 0
    local motorDir=data.motor and data.motor.direction or 1

    writeAt(mon,2,3,"ROTATION",colors.yellow)
    writeAt(mon,2,4,string.format("SHAFT %7.1f RPM",rpm),colors.white)
    writeAt(mon,2,5,string.format("RAW   %7.1f  x %s",raw,tostring(mult)),colors.lightGray)
    writeAt(mon,2,6,string.format("MOTOR %7.1f RPM  DIR %s",motorRpm,motorDir < 0 and "-" or "+"),colors.lightGray)

    local bw=math.max(10,math.floor((mainRight-5)/2))
    local bx1=2
    local bx2=bx1+bw+2

    button(mon,bx1,9,bw,"32 RPM",colors.blue,"command","motor_32")
    button(mon,bx2,9,bw,"64 RPM",colors.blue,"command","motor_64")
    button(mon,bx1,11,bw,"128 RPM",colors.cyan,"command","motor_128")
    button(mon,bx2,11,bw,"MOTOR STOP",colors.red,"command","motor_stop")

    button(mon,bx1,14,bw,"GEN "..(data.control.genClutchEngaged and "ON" or "CUT"),
        data.control.genClutchEngaged and colors.green or colors.red,
        "command",data.control.genClutchEngaged and "gen_off" or "gen_on")
    button(mon,bx2,14,bw,"APPLY RUN",colors.blue,"command","running_topology")

    if h>=17 then
        writeAt(mon,2,17,"Sensor polarity and motor direction:",colors.yellow)
        writeAt(mon,2,18,"profilectl / pkgctl",colors.lightGray)
    end
end

local function drawData(mon,data)
    local mainRight=drawSideNav(mon,"data")
    if not data then
        writeAt(mon,2,4,"Waiting for telemetry...",colors.orange)
        return
    end

    writeAt(mon,2,3,"POWER",colors.yellow)
    writeAt(mon,2,4,string.format("RPM    %7.1f",data.power.rpm))
    writeAt(mon,20,4,string.format("LOAD %5.1f%%",data.power.load))
    writeAt(mon,2,5,string.format("STRESS %.0f / %.0f SU",data.power.stress,data.power.capacity),colors.lightGray)

    writeAt(mon,2,7,"BOILER",colors.yellow)
    writeAt(mon,2,8,"WATER")
    bar(mon,10,8,math.max(8,mainRight-18),data.boiler.water,colors.blue)
    writeAt(mon,math.max(12,mainRight-6),8,string.format("%3.0f%%",data.boiler.water))
    writeAt(mon,2,9,"HEAT")
    bar(mon,10,9,math.max(8,mainRight-18),data.boiler.heat,colors.red)
    writeAt(mon,math.max(12,mainRight-6),9,string.format("%3.0f%%",data.boiler.heat))

    writeAt(mon,2,11,"BATTERY",colors.yellow)
    bar(mon,2,12,math.max(10,mainRight-10),data.battery.percent,
        data.battery.percent<15 and colors.red or data.battery.percent<35 and colors.orange or colors.lime)
    writeAt(mon,math.max(12,mainRight-7),12,string.format("%5.1f%%",data.battery.percent))

    writeAt(mon,2,14,"CLUTCHES",colors.yellow)
    writeAt(mon,2,15,"MAIN "..(data.control.mainClutchEngaged and "ON" or "CUT"),
        data.control.mainClutchEngaged and colors.lime or colors.red)
    writeAt(mon,15,15,"GEN "..(data.control.genClutchEngaged and "ON" or "CUT"),
        data.control.genClutchEngaged and colors.lime or colors.red)
    writeAt(mon,27,15,"ALT "..(data.control.alternatorClutchEngaged and "ON" or "CUT"),
        data.control.alternatorClutchEngaged and colors.lime or colors.red)

    writeAt(mon,2,17,"MOTOR "..string.format("%.1f RPM",data.motor.rpm),colors.lightGray)
end

local function drawLogs(mon,events)
    local mainRight=drawSideNav(mon,"logs")
    writeAt(mon,2,3,"EVENT LOG",colors.yellow)

    local row=4
    for _,e in ipairs(events or {}) do
        if eventVisible(e) then
            if row>select(2,mon.getSize()) then break end
            local prefix=fmtTime(e.timestamp).." "..tostring(e.code or "EVENT")
            writeClipped(mon,2,row,prefix,mainRight,levelColor(e.level))
            local msg=tostring(e.message or "")
            local msgX=math.min(mainRight-2,#prefix+4)
            if msgX<mainRight then writeClipped(mon,msgX,row,msg,mainRight,colors.lightGray) end
            row=row+1
        end
    end

    if row==4 then writeAt(mon,2,5,"No matching events.",colors.gray) end
end

local function drawDebug(mon,data,sourceFresh,events,pending,debugInfo)
    local mainRight=drawSideNav(mon,"debug")
    writeAt(mon,2,3,"DEBUG",colors.yellow)
    writeAt(mon,2,5,"Link: "..(sourceFresh and "OK" or "STALE"),sourceFresh and colors.lime or colors.red)
    writeAt(mon,2,6,"Backend: "..tostring(debugInfo and debugInfo.display and debugInfo.display.backend or "-"))
    writeAt(mon,2,7,"Machine nodes: "..tostring(debugInfo and debugInfo.nodes and #debugInfo.nodes or 0))
    if data then
        writeAt(mon,2,9,"State: "..tostring(data.control.state))
        writeAt(mon,2,10,string.format("RPM %.2f  LOAD %.1f%%",data.power.rpm,data.power.load))
        writeAt(mon,2,11,string.format("Water %.1f%% Heat %.1f%% Bat %.1f%%",data.boiler.water,data.boiler.heat,data.battery.percent))
    end
    if pending then writeAt(mon,2,13,"Pending: "..tostring(pending.command),colors.orange) end
end

function M.draw(mon,page,data,sourceFresh,latestEvent,events,pending,debugInfo)
    resetHits()
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
    mon.setCursorPos(1,1)

    page=page or "control"
    drawHeader(mon,page,data,debugInfo and debugInfo.machineLabel)

    if page=="gen" then
        drawGen(mon,data)
    elseif page=="data" then
        drawData(mon,data)
    elseif page=="logs" then
        drawLogs(mon,events or {})
    elseif page=="debug" then
        drawDebug(mon,data,sourceFresh,events or {},pending,debugInfo or {})
    else
        drawControl(mon,data,sourceFresh,pending)
    end
end

function M.actionAt(x,y)
    for _,h in ipairs(hitboxes) do
        if x>=h.x1 and x<=h.x2 and y>=h.y1 and y<=h.y2 then
            return h.action,h.arg
        end
    end
    return nil
end

return M
