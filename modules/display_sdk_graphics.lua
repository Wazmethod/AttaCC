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
    -- Compact layout: categories in the bottom bar, subcategories under
    -- the title. A 3x1 angled screen is wide but short.
    local categories,firstView={},{}
    for _,v in ipairs(descriptor.views or {}) do
        local cat=v.category or "main"
        if cat~="maintenance" and cat~="technical" and not firstView[cat] then
            firstView[cat]=v
            categories[#categories+1]={id=cat,label=v.categoryLabel or cat,view=v.id}
        end
    end
    local selectedView
    for _,v in ipairs(descriptor.views or {}) do
        if v.id==options.view then selectedView=v;break end
    end
    selectedView=selectedView or (descriptor.views or {})[1]
    local selectedCategory=selectedView and (selectedView.category or "main") or "main"
    local subs={}
    for _,v in ipairs(descriptor.views or {}) do
        if (v.category or "main")==selectedCategory then
            subs[#subs+1]={id=v.id,view=v.id,label=v.subcategory or v.label}
        end
    end
    local hasSubs=w>=155 and h>=85 and #subs>1
    local contentTop=hasSubs and 45 or 26
    local rowHeight=(h<155) and 15 or 22
    local footerY=h-21
    local usable=math.max(1,footerY-contentTop-4)
    local budget=math.max(1,math.floor(usable/rowHeight))
    local pages,reason,view=layout.pages(descriptor,options.view,w,budget+5)
    if reason then return {ok=false,warning=reason,hitboxes={}} end
    local page=math.max(1,math.min(#pages,math.floor(tonumber(options.page) or 1)))
    local data=index(descriptor.data)
    local controls=index(descriptor.controls)
    local graphs=index(descriptor.graphs)
    local banners=index(descriptor.banners)
    local titleWidth=math.max(20,math.floor(w/2)-52)
    label(target,8,8,(descriptor.title or "ATTACC").." / "..(pages[page].label or view.label or ""),titleWidth,C.accent)
    gfx.line(target,8,21,w-9,21,C.border)
    local function tabs(tabs,y,active,x,totalWidth,height)
        if #tabs==0 then return end
        local step=totalWidth/#tabs
        for i,tab in ipairs(tabs) do
            local left=math.floor(x+(i-1)*step)
            local right=math.floor(x+i*step)-2
            local width=right-left+1
            if width>=16 then
                local selected=tab.id==active
                gfx.button(target,hitboxes,left,y,width,height,tab.label,
                    selected and C.accent or C.panel,
                    "display.view."..tab.view,nil,C,selected)
            end
        end
    end
    if hasSubs then tabs(subs,24,view.id,8,w-16,17) end
    -- SDK compact panel layout: display existing exported data side by side.
    -- Controls use the application's declared IDs; never synthesize commands.
    if view.layout=="panels" then
        local contentBottom=h-24
        local panelY=25
        local panelH=contentBottom-panelY
        local gap=5
        local leftX=7
        local leftW=math.floor((w-21)*0.68)
        local rightX=leftX+leftW+gap
        local rightW=w-rightX-7
        gfx.frame(target,leftX,panelY,leftW,panelH,C.border)
        gfx.frame(target,rightX,panelY,rightW,panelH,C.border)
        label(target,leftX+6,panelY+5,view.panelTitle or "PLANT",leftW-12,C.accent)
        label(target,rightX+6,panelY+5,view.controlTitle or "CONTROL",rightW-12,C.accent)
        local ids=view.data or {}
        local cols=math.min(3,math.max(1,#ids))
        local metricGap=5
        local innerX=leftX+6
        local innerW=leftW-12
        local cardW=math.floor((innerW-(cols-1)*metricGap)/cols)
        local cardY=panelY+17
        local cardH=math.max(19,math.min(27,panelH-23))
        for i=1,cols do
            local datum=data[ids[i]]
            local cx=innerX+(i-1)*(cardW+metricGap)
            if cardW>=20 and datum then
                gfx.frame(target,cx,cardY,cardW,cardH,
                    (i==1 and colors.yellow) or (i==2 and colors.orange) or colors.lime)
                label(target,cx+4,cardY+3,datum.shortLabel or datum.label or ids[i],
                    cardW-8,C.accent)
                label(target,cx+4,cardY+12,val(datum.value),cardW-8,C.text)
            end
        end
        local buttons=view.controls or {}
        local btnGap=4
        local btnCols=2
        local buttonW=math.floor((rightW-12-btnGap)/btnCols)
        local maxRows=math.max(1,math.floor((panelH-19)/17))
        for i=1,math.min(#buttons,maxRows*btnCols) do
            local ctrl=controls[buttons[i]]
            if ctrl then
                local col=(i-1)%btnCols
                local row=math.floor((i-1)/btnCols)
                local bx=rightX+5+col*(buttonW+btnGap)
                local by=panelY+16+row*17
                if buttonW>=20 then
                    gfx.button(target,hitboxes,bx,by,buttonW,14,ctrl.label,
                        C.panel,ctrl.id,nil,C,ctrl.enabled~=false)
                    if ctrl.enabled==false then hitboxes[#hitboxes]=nil end
                end
            end
        end
    else
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
                gfx.button(target,hitboxes,9,y-1,w-18,rowHeight-2,name,
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
            gfx.frame(target,9,y-1,w-18,rowHeight-2,C.border)
            for j=2,#samples do
                local a,b=samples[j-1].value,samples[j].value
                if type(a)=="number" and type(b)=="number" then
                    local x0=11+math.floor((j-2)*(w-23)/math.max(1,#samples-1))
                    local x1=11+math.floor((j-1)*(w-23)/math.max(1,#samples-1))
                    local y0=y+rowHeight-5-math.floor((a-low)/(high-low)*(rowHeight-7))
                    local y1=y+rowHeight-5-math.floor((b-low)/(high-low)*(rowHeight-7))
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
                gfx.fill(target,9,y-1,w-18,rowHeight-2,C.panel)
                label(target,13,y+2,message,w-26,C.accent)
            end
        else
            label(target,12,y,name..": "..val(ref and ref.value),w-24)
        end
    end
    -- Compact previous/next edges, with the active category tabs in between.
    end -- panel/non-panel renderer
    local navWidth=math.min(55,math.max(32,math.floor(w/7)))
    local navY=h-20
    if #pages>1 then
        gfx.button(target,hitboxes,8,navY,navWidth,16,"PREV",C.panel,"display.previous",nil,C)
        gfx.button(target,hitboxes,w-8-navWidth,navY,navWidth,16,"NEXT",C.panel,"display.next",nil,C)
    end
    local middleX=8+navWidth+4
    local middleW=w-16-2*navWidth-8
    if #categories>0 and middleW>=18 then
        tabs(categories,navY,selectedCategory,middleX,middleW,16)
    end
    if options.graphicsAvailable ~= false then
        -- A dedicated button on the far right; graphics hitbox matches drawing.
        gfx.button(target,hitboxes,math.floor(w/2)-36,3,72,17,"TEXT MODE",C.panel,"display.toggle",nil,C)
    end
    label(target,math.max(8,w-65),h-30,"PAGE "..page.."/"..#pages,60,C.muted)
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
