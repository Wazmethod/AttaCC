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
    -- The monitor's categories are the SDK exports, not app-defined views.
    local categories={
        {id="data",label="DATA",view="data"},
        {id="graphs",label="GRAPHS",view="graphs"},
        {id="controls",label="CONTROLS",view="controls"}
    }
    local selectedCategory=options.exportCategory or "data"
    if selectedCategory~="data" and selectedCategory~="graphs"
        and selectedCategory~="controls" then selectedCategory="data" end
    local source=descriptor[selectedCategory] or {}
    local subs={}
    for _,item in ipairs(source) do
        if item.id then
            subs[#subs+1]={id=item.id,view=item.id,label=item.label or item.id}
        end
    end
    -- Page groups are derived from exports. Each page uses all available
    -- vertical space rather than allocating one full page per exported item.
    local graphColumns=w>=155 and 2 or 1
    local graphRows=math.max(1,math.floor((h-44)/36))
    local graphCount=graphColumns*graphRows
    local dataCount=math.max(1,math.floor((h-44)/10))
    local controlCount=math.max(1,math.floor((h-44)/14))*2
    local itemsPerPage=selectedCategory=="graphs" and graphCount
        or (selectedCategory=="data" and dataCount or controlCount)
    local totalPages=math.max(1,math.ceil(#subs/itemsPerPage))
    local requested=options.exportItem
    local page=1
    if requested then
        for i,sub in ipairs(subs) do
            if sub.id==requested then page=math.ceil(i/itemsPerPage);break end
        end
    end
    local start=(page-1)*itemsPerPage+1
    local stop=math.min(#subs,start+itemsPerPage-1)
    local selectedView={id="sdk_export",label=selectedCategory:upper(),
        layout="dashboard",category=selectedCategory,data={},graphs={},controls={}}
    for i=start,stop do
        if selectedCategory=="data" then
            selectedView.data[#selectedView.data+1]=subs[i].id
        elseif selectedCategory=="graphs" then
            selectedView.graphs[#selectedView.graphs+1]=subs[i].id
        end
    end
    local originalDescriptor=descriptor
    local virtual={}
    for k,v in pairs(descriptor) do virtual[k]=v end
    virtual.views={selectedView}
    descriptor=virtual
    options.view="sdk_export"
    local contentTop=17
    local footerTop=h-25
    local rowCount=math.max(1,stop-start+1)
    local rowHeight=math.max(9,math.floor((footerTop-contentTop-2)/rowCount))
    local budget=rowCount+5
    local pages,reason,view=layout.pages(descriptor,options.view,w,budget+5)
    if reason then return {ok=false,warning=reason,hitboxes={}} end
    local data=index(descriptor.data)
    local controls=index(descriptor.controls)
    local graphs=index(descriptor.graphs)
    local banners=index(descriptor.banners)
    label(target,5,3,descriptor.title or "ATTACC",math.max(20,math.floor(w/2)-36),C.accent)
    gfx.line(target,5,13,w-6,13,C.border)
    if selectedCategory=="controls" then
        local count=stop-start+1
        local columns=w>=160 and 2 or 1
        local rows=math.ceil(count/columns)
        local gap=4
        local cellW=math.floor((w-14-(columns-1)*gap)/columns)
        local cellH=math.max(13,math.min(19,math.floor((footerTop-contentTop-2)/math.max(1,rows))))
        for i=start,stop do
            local ctrl=controls[subs[i].id]
            if ctrl then
                local n=i-start
                local x=7+(n%columns)*(cellW+gap)
                local y=contentTop+math.floor(n/columns)*cellH
                if y+cellH<=footerTop then
                    local state=ctrl.state or (ctrl.enabled==false and "OFF" or "READY")
                    local caption=(ctrl.label or ctrl.id).." "..state
                    if ctrl.monitor==true and ctrl.enabled~=false then
                        local pending=options.pendingControl==ctrl.id
                        gfx.button(target,hitboxes,x,y,cellW,cellH-2,
                            pending and ("CONFIRM "..caption) or caption,
                            pending and C.warn or C.panel,
                            "display.control."..ctrl.id,nil,C,pending)
                    else
                        gfx.frame(target,x,y,cellW,cellH-2,C.border)
                        label(target,x+3,y+3,caption,cellW-6,C.muted)
                    end
                end
            end
        end
    end
    if selectedCategory=="graphs" then
        local gap=5
        local columns=graphColumns
        local count=stop-start+1
        local rows=math.ceil(count/columns)
        local cellW=math.floor((w-14-gap*(columns-1))/columns)
        local cellH=math.floor((footerTop-contentTop-2-gap*(rows-1))/math.max(1,rows))
        for i=start,stop do
            local n=i-start
            local x=7+(n%columns)*(cellW+gap)
            local y=contentTop+math.floor(n/columns)*(cellH+gap)
            local graph=graphs[subs[i].id]
            if graph and cellH>=16 then
                gfx.frame(target,x,y,cellW,cellH,C.border)
                label(target,x+4,y+3,graph.label or graph.id,cellW-8,C.accent)
                local samples=graph.samples or {}
                local low,high=nil,nil
                for _,sample in ipairs(samples) do
                    local value=tonumber(sample.value)
                    if value then
                        low=math.min(low or value,value)
                        high=math.max(high or value,value)
                    end
                end
                if low and high then
                    if high<=low then high=low+1 end
                    local plotY=y+12
                    local plotH=math.max(2,cellH-15)
                    for j=2,#samples do
                        local va=tonumber(samples[j-1].value)
                        local vb=tonumber(samples[j].value)
                        if va and vb then
                            local x0=x+3+math.floor((j-2)*(cellW-7)/math.max(1,#samples-1))
                            local x1=x+3+math.floor((j-1)*(cellW-7)/math.max(1,#samples-1))
                            local y0=plotY+plotH-1-math.floor((va-low)/(high-low)*(plotH-1))
                            local y1=plotY+plotH-1-math.floor((vb-low)/(high-low)*(plotH-1))
                            gfx.line(target,x0,y0,x1,y1,C.accent)
                        end
                    end
                end
            end
        end
    end
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
                label(target,cx+4,cardY+3,(view.metricLabels and view.metricLabels[ids[i]]) or datum.label or ids[i],
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
    elseif selectedCategory=="data" then
    for i,item in ipairs(pages[1].items) do
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
    end -- close panel/dashboard branch
    -- Two thin footer rows: export categories, then page navigator.
    local catY=h-24
    local catW=(w-12)/3
    for i,cat in ipairs(categories) do
        local x=math.floor(5+(i-1)*catW)
        local width=math.floor(5+i*catW)-x-2
        gfx.button(target,hitboxes,x,catY,width,10,cat.label,
            cat.id==selectedCategory and C.accent or C.panel,
            "display.export."..cat.id,nil,C,cat.id==selectedCategory)
    end
    local navY=h-12
    local navWidth=math.min(35,math.floor(w/7))
    if page>1 then
        gfx.button(target,hitboxes,5,navY,navWidth,10,"PREV",C.panel,
            "display.item."..selectedCategory.."."..subs[start-1].id,nil,C)
    end
    if page<totalPages then
        gfx.button(target,hitboxes,w-navWidth-5,navY,navWidth,10,"NEXT",C.panel,
            "display.item."..selectedCategory.."."..subs[stop+1].id,nil,C)
    end
    local pageName=selectedCategory:upper().." "..page.."/"..totalPages
    local captionX=5+navWidth+4
    label(target,captionX,navY+2,pageName,w-2*captionX,C.muted)
    if options.graphicsAvailable ~= false then
        gfx.button(target,hitboxes,math.floor(w/2)-24,2,48,10,"TEXT MODE",
            C.panel,"display.toggle",nil,C)
    end
    local out={}
    for _,hit in ipairs(hitboxes) do
        out[#out+1]={x1=hit.x1,y1=hit.y1,x2=hit.x2,y2=hit.y2,id=hit.action}
    end
    return {ok=true,backend="ccgraphics",page=page,pageCount=totalPages,view=view.id,
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
