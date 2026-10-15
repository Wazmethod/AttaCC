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
    local grouped=h>=135
    local contentTop=grouped and 78 or 26
    local budget=math.max(1,math.floor((h-contentTop-31)/rowHeight))
    local pages,reason,view=layout.pages(descriptor,options.view,w,budget+5)
    if reason then return {ok=false,warning=reason,hitboxes={}} end
    local page=math.max(1,math.min(#pages,math.floor(tonumber(options.page) or 1)))
    local data=index(descriptor.data)
    local controls=index(descriptor.controls)
    local graphs=index(descriptor.graphs)
    local banners=index(descriptor.banners)
    label(target,8,8,(descriptor.title or "ATTACC").." / "..(pages[page].label or view.label or ""),w-100,C.accent)
    gfx.line(target,8,21,w-9,21,C.border)
    if grouped then
        -- Categories are SDK view metadata, not application-specific controls.
        local categories,firstView={},{}
        for _,v in ipairs(descriptor.views or {}) do
            local cat=v.category or "main"
            if cat~="maintenance" and cat~="technical" then
                if not firstView[cat] then
                    firstView[cat]=v
                    categories[#categories+1]={id=cat,label=v.categoryLabel or cat}
                end
            end
        end
        local selectedCategory=view.category or "main"
        local function tabs(tabs,y,active,kind)
            if #tabs==0 then return end
            local tw=math.floor((w-16)/#tabs)
            for i,tab in ipairs(tabs) do
                local x=8+(i-1)*tw
                local width=(i==#tabs) and (w-8-x) or (tw-2)
                if width>=16 then
                    local selected=tab.id==active
                    gfx.button(target,hitboxes,x,y,width,19,tab.label,
                        selected and C.accent or C.panel,
                        "display.view."..tab.view,nil,C,selected)
                end
            end
        end
        for _,cat in ipairs(categories) do cat.view=firstView[cat.id].id end
        tabs(categories,26,selectedCategory,"category")
        local subs={}
        for _,v in ipairs(descriptor.views or {}) do
            if (v.category or "main")==selectedCategory then
                subs[#subs+1]={id=v.id,view=v.id,label=v.subcategory or v.label}
            end
        end
        tabs(subs,49,view.id,"subcategory")
    end
    for i,item in ipairs(pages[page].items) do
        local y=contentTop+(i-1)*rowHeight
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
            local low,high=nil,nil
            for _,s in ipairs(samples) do
                local v=s.value
                if type(v)=="number" then
                    low=math.min(low or v,v)
                    high=math.max(high or v,v)
                end
            end
            low=tonumber(graph and graph.min) or low or 0
            high=tonumber(graph and graph.max) or high or (low+1)
            if high<=low then high=low+1 end
            gfx.frame(target,9,y-2,w-18,19,C.border)
            for j=2,#samples do
                local a,b=samples[j-1].value,samples[j].value
                if type(a)=="number" and type(b)=="number" then
                    local x0=11+math.floor((j-2)*(w-23)/math.max(1,#samples-1))
                    local x1=11+math.floor((j-1)*(w-23)/math.max(1,#samples-1))
                    local y0=y+14-math.floor((a-low)/(high-low)*14)
                    local y1=y+14-math.floor((b-low)/(high-low)*14)
                    gfx.line(target,x0,y0,x1,y1,C.accent)
                end
            end
            label(target,13,y+2,name.." "..(last and val(last.value) or "--"),w-28)
        elseif item.type=="banner" then
            local banner=banners[item.id or ""]
            if banner then
                local message=tostring(banner.value == nil and "" or banner.value)
                local width=math.max(1,math.floor((w-26)/4))
                local offset=math.floor(tonumber(options.scrollOffset) or 0)
                if banner.scroll ~= false and #message>width then
                    local cycle=message.."   "
                    local shift=offset % #cycle
                    message=cycle:sub(shift+1)..cycle:sub(1,shift)
                    while #message<width do message=message..cycle end
                end
                gfx.fill(target,9,y-2,w-18,19,C.panel)
                label(target,13,y+4,message,w-26,C.accent)
            end
        else
            label(target,12,y,name..": "..val(ref and ref.value),w-24)
        end
    end
    local fy=h-25
    local hasMaintenance=false
    for _,viewDef in ipairs(descriptor.views or {}) do
        if (viewDef.category=="maintenance" or viewDef.category=="technical")
           and viewDef.persistent then hasMaintenance=true;break end
    end
    if #pages>1 and hasMaintenance then
        local third=math.floor((w-16)/3)
        gfx.button(target,hitboxes,8,fy,third-3,19,"PREV",C.panel,"display.previous",nil,C)
        gfx.button(target,hitboxes,8+third,fy,third-3,19,"NEXT",C.panel,"display.next",nil,C)
        gfx.button(target,hitboxes,8+third*2,fy,w-16-third*2,19,"MAINT",C.panel,"display.maintenance",nil,C)
    elseif #pages>1 then
        local split=math.floor(w/2)
        gfx.button(target,hitboxes,8,fy,split-12,19,"PREV",C.panel,"display.previous",nil,C)
        gfx.button(target,hitboxes,split+3,fy,w-split-11,19,"NEXT",C.panel,"display.next",nil,C)
    elseif hasMaintenance then
        gfx.button(target,hitboxes,8,fy,w-16,19,"MAINT",C.panel,"display.maintenance",nil,C)
    end
    if options.graphicsAvailable ~= false then
        -- A dedicated button on the far right; graphics hitbox matches drawing.
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
    -- CC:Graphics hitboxes cover pixel rectangles, not text rows.
    for _,hit in ipairs(result and result.hitboxes or {}) do
        if x>=hit.x1 and x<=hit.x2 and y>=hit.y1 and y<=hit.y2 then
            return hit.id
        end
    end
    return nil
end
return M
