-- Declarative AttaCC CC:Graphics renderer (v1.1 preview).
-- Uses the same view/page descriptor and hitbox contract as display_sdk.
local layout = require("lib.display_sdk")
local gfx = require("lib.display_graphics")
local M = {}
local C = {bg=colors.black,panel=colors.gray,border=colors.lightGray,text=colors.white,
           accent=colors.cyan,muted=colors.lightGray,ok=colors.lime,warn=colors.orange}
local function val(v)
    if v == nil then return "--" end
    return tostring(v)
end
local function index(items)
    local out={}
    for _,v in ipairs(items or {}) do if v.id then out[v.id]=v end end
    return out
end
local function label(t,x,y,s,w,color)
    gfx.text(t,x,y,gfx.fitText(s,math.max(0,w),1),color or C.text,1)
end
function M.render(target, descriptor, options)
    options=options or {}
    if not target or type(target.setGraphicsMode)~="function" then
        return {ok=false,warning="graphics_unavailable",hitboxes={}}
    end
    local ok,err=pcall(target.setGraphicsMode,options.graphicsMode or 1)
    if not ok then return {ok=false,warning="graphics_unavailable",error=tostring(err),hitboxes={}} end
    local sized,w,h=pcall(target.getSize,options.graphicsMode or 1)
    if not sized or type(w)~="number" or type(h)~="number" then
        return {ok=false,warning="graphics_geometry_unavailable",hitboxes={}}
    end
    gfx.fill(target,0,0,w,h,C.bg)
    local hitboxes={}
    if w<92 or h<75 then
        label(target,5,8,"DISPLAY TOO SMALL",w-10,C.warn)
        label(target,5,23,tostring(w).."X"..tostring(h).." - MIN 92X75",w-10)
        return {ok=false,warning="resolution_too_low",width=w,height=h,minWidth=92,minHeight=75,hitboxes={}}
    end
    -- Convert pixel space to row budget; each item consumes one uniform card row.
    local rowHeight=24
    local budget=math.max(1,math.floor((h-62)/rowHeight))
    local pages,reason,view=layout.pages(descriptor,options.view,w,budget+5)
    if reason then return {ok=false,warning=reason,hitboxes={}} end
    local page=math.max(1,math.min(#pages,math.floor(tonumber(options.page) or 1)))
    local data=index(descriptor.data)
    local controls=index(descriptor.controls)
    local graphs=index(descriptor.graphs)
    label(target,8,8,(descriptor.title or "ATTACC").." / "..(pages[page].label or view.label or ""),w-16,C.accent)
    gfx.line(target,8,21,w-9,21,C.border)
    for i,item in ipairs(pages[page].items) do
        local y=26+(i-1)*rowHeight
        local ref=(item.type=="control" and controls or data)[item.id or ""]
        local name=item.label or (ref and ref.label) or item.id or ""
        if item.type=="header" then
            label(target,10,y,name,w-20,C.accent)
        elseif item.type=="control" then
            local ctrl=controls[item.id or ""]
            if ctrl then
                local enabled=ctrl.enabled~=false
                gfx.button(target,hitboxes,9,y-2,w-18,19,name,
                    enabled and C.panel or C.bg,item.id,nil,C,enabled)
                if not enabled then hitboxes[#hitboxes]=nil end
            end
        elseif item.type=="graph" then
            local graph=graphs[item.id or ""]
            local samples=graph and graph.samples or {}
            local last=samples[#samples]
            label(target,12,y,name.." "..(last and val(last.value) or "--"),w-24)
        else
            label(target,12,y,name..": "..val(ref and ref.value),w-24)
        end
    end
    local fy=h-25
    if #pages>1 then
        local split=math.floor(w/2)
        gfx.button(target,hitboxes,8,fy,split-12,19,"PREV",C.panel,"display.previous",nil,C)
        gfx.button(target,hitboxes,split+3,fy,w-split-11,19,"NEXT",C.panel,"display.next",nil,C)
    end
    if options.onToggleRenderer then
        gfx.button(target,hitboxes,w-80,3,72,17,"TEXT MODE",C.panel,"display.toggle",nil,C)
    end
    label(target,8,h-7,"PAGE "..page.."/"..#pages,w-16,C.muted)
    local out={}
    for _,hit in ipairs(hitboxes) do
        out[#out+1]={x1=hit.x1,y1=hit.y1,x2=hit.x2,y2=hit.y2,id=hit.action}
    end
    return {ok=true,backend="ccgraphics",page=page,pageCount=#pages,view=view.id,
            width=w,height=h,hitboxes=out}
end
function M.hit(result,x,y)
    return layout.hit(result,x,y)
end
return M
