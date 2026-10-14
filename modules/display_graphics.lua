local M = {}

M.FONT = {
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
    ["W"]={"101","111","111","111","101"}, ["X"]={"101","101","010","101","101"},
    ["Y"]={"101","101","010","010","010"}, ["Z"]={"111","001","010","100","111"},
    ["0"]={"111","101","101","101","111"}, ["1"]={"010","110","010","010","111"},
    ["2"]={"110","001","010","100","111"}, ["3"]={"110","001","010","001","110"},
    ["4"]={"101","101","111","001","001"}, ["5"]={"111","100","110","001","110"},
    ["6"]={"011","100","110","101","010"}, ["7"]={"111","001","010","010","010"},
    ["8"]={"010","101","010","101","010"}, ["9"]={"010","101","011","001","110"},
    ["."]={"000","000","000","000","010"}, [":"]={"000","010","000","010","000"},
    ["-"]={"000","000","111","000","000"}, ["/"]={"001","001","010","100","100"},
    ["%"]={"101","001","010","100","101"}, [" "]={"000","000","000","000","000"},
    ["<"]={"001","010","100","010","001"}, [">"]={"100","010","001","010","100"},
    ["["]={"110","100","100","100","110"}, ["]"]={"011","001","001","001","011"},
    ["_"]={"000","000","000","000","111"}, ["+"]={"000","010","111","010","000"},
    ["#"]={"101","111","101","111","101"},
}

function M.fill(target,x,y,w,h,color)
    if not target or w<=0 or h<=0 then return end
    target.drawPixels(math.floor(x),math.floor(y),color,math.floor(w),math.floor(h))
end

function M.frame(target,x,y,w,h,color)
    M.fill(target,x,y,w,1,color)
    M.fill(target,x,y+h-1,w,1,color)
    M.fill(target,x,y,1,h,color)
    M.fill(target,x+w-1,y,1,h,color)
end

function M.textWidth(value,scale)
    return #tostring(value or "") * 4 * (scale or 1)
end

function M.fitText(value,maxWidth,scale)
    value=tostring(value or "")
    scale=scale or 1
    local maxChars=math.max(0,math.floor((maxWidth or 0)/(4*scale)))
    if #value<=maxChars then return value end
    if maxChars<=3 then return value:sub(1,maxChars) end
    return value:sub(1,maxChars-3).."..."
end

function M.text(target,x,y,value,color,scale)
    value=tostring(value or ""):upper()
    scale=scale or 1
    local cursor=x
    for i=1,#value do
        local glyph=M.FONT[value:sub(i,i)] or M.FONT["#"]
        for gy=1,5 do
            for gx=1,3 do
                if glyph[gy]:sub(gx,gx)=="1" then
                    M.fill(target,cursor+(gx-1)*scale,y+(gy-1)*scale,scale,scale,color)
                end
            end
        end
        cursor=cursor+4*scale
    end
    return cursor
end

function M.line(target,x0,y0,x1,y1,color)
    x0=math.floor(x0); y0=math.floor(y0); x1=math.floor(x1); y1=math.floor(y1)
    local dx=math.abs(x1-x0)
    local sx=x0<x1 and 1 or -1
    local dy=-math.abs(y1-y0)
    local sy=y0<y1 and 1 or -1
    local err=dx+dy
    while true do
        target.setPixel(x0,y0,color)
        if x0==x1 and y0==y1 then break end
        local e2=2*err
        if e2>=dy then err=err+dy; x0=x0+sx end
        if e2<=dx then err=err+dx; y0=y0+sy end
    end
end

function M.addHit(hitboxes,x,y,w,h,action,arg)
    table.insert(hitboxes,{
        x1=math.floor(x),y1=math.floor(y),
        x2=math.floor(x+w-1),y2=math.floor(y+h-1),
        action=action,arg=arg,
    })
end

function M.hit(hitboxes,x,y)
    for _,box in ipairs(hitboxes or {}) do
        if x>=box.x1 and x<=box.x2 and y>=box.y1 and y<=box.y2 then
            return box.action,box.arg
        end
    end
    return nil
end

function M.panel(target,x,y,w,h,title,colorset)
    local C=colorset or {}
    M.fill(target,x,y,w,h,C.panelDark or colors.black)
    M.frame(target,x,y,w,h,C.border or colors.lightGray)
    if title then M.text(target,x+5,y+4,title,C.accent or colors.cyan,1) end
end

function M.button(target,hitboxes,x,y,w,h,label,color,action,arg,colorset,active)
    local C=colorset or {}
    M.fill(target,x,y,w,h,active and (C.accent or colors.cyan) or color)
    M.frame(target,x,y,w,h,active and (C.white or colors.white) or (C.border or colors.lightGray))
    local tw=M.textWidth(label,1)
    local tx=x+math.max(3,math.floor((w-tw)/2))
    local ty=y+math.max(2,math.floor((h-5)/2))
    M.text(target,tx,ty,label,C.white or colors.white,1)
    M.addHit(hitboxes,x,y,w,h,action,arg)
end

function M.meter(target,x,y,w,h,value,color,border)
    value=math.max(0,math.min(100,tonumber(value) or 0))
    M.fill(target,x,y,w,h,colors.gray)
    local fw=math.floor(w*value/100)
    if fw>0 then M.fill(target,x,y,fw,h,color) end
    M.frame(target,x,y,w,h,border or colors.lightGray)
end

return M
