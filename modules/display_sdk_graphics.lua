-- Declarative AttaCC CC:Graphics renderer (v1.1 preview).
-- Uses the same view/page descriptor and hitbox contract as display_sdk.
local layout = require("lib.display_sdk")
local gfx = require("lib.display_graphics")
local M = {}
local C = {bg=colors.black,panel=colors.gray,border=colors.lightGray,text=colors.white,
           accent=colors.cyan,muted=colors.lightGray,ok=colors.lime,warn=colors.orange}
local function val(v)
    if v == nil then return "--" end
    if type(v)=="boolean" then return v and "ON" or "OFF" end
    if type(v)=="number" then
        if v~=v or v==math.huge or v==-math.huge then return "--" end
        local rounded=v>=0 and math.floor(v*100+0.5)/100
            or math.ceil(v*100-0.5)/100
        local formatted=string.format("%.2f",rounded)
        return (formatted:gsub("%.?0+$",""))
    end
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
    if options.viewMode=="views" then
        local views={}
        for _,v in ipairs(descriptor.views or {}) do
            if v.category~="maintenance" and v.category~="technical" then
                views[#views+1]=v
            end
        end
        local current=views[1]
        for _,v in ipairs(views) do
            if v.id==options.view then current=v;break end
        end
        if not current then return {ok=false,warning="no_views"} end
        local roots,children={},{}
        for _,v in ipairs(views) do
            if type(v.parent)=="string" and v.parent~="" then
                children[v.parent]=children[v.parent] or {}
                children[v.parent][#children[v.parent]+1]=v
            else roots[#roots+1]=v end
        end
        local activeRoot=current.parent or current.id
        local data=index(descriptor.data)
        local controls=index(descriptor.controls)
        local graphs=index(descriptor.graphs)
        local heading=gfx.fitText((current.label or activeRoot):upper(),math.max(12,w-108),1)
        gfx.text(target,math.floor((w-gfx.textWidth(heading,1))/2),3,heading,C.accent,1)
        gfx.line(target,5,13,w-6,13,C.border)
        local subtabs=children[activeRoot] or {}
        local rootView
        for _,v in ipairs(roots) do if v.id==activeRoot then rootView=v;break end end
        local sourceNav=(rootView and rootView.sourceNavigation) or current.sourceNavigation
        local top=sourceNav and 46 or 31 -- parent source selector occupies its own row
        local bottom=h-16
        -- Navigation belongs to the framework chrome, never to content cards.
        -- Older applications may still declare these actions as widgets.
        local customNav=current.navigation
        local navigationActions={}
        for _,nav in ipairs({customNav,sourceNav}) do
            if type(nav)=="table" then
                if nav.previous then navigationActions[nav.previous]=true end
                if nav.next then navigationActions[nav.next]=true end
            end
        end
        local widgets,actions={},{}
        for _,widget in ipairs(current.widgets or {}) do
            if widget.type=="action" then
                if not navigationActions[widget.id] then
                    actions[#actions+1]=widget
                end
            else
                if not (current.dynamicRows==true and widget.type=="machine-row"
                    and (not data[widget.id] or data[widget.id].value=="--"
                        or data[widget.id].value==nil)) then
                    widgets[#widgets+1]=widget
                end
            end
        end
        -- Generate one card per category from the selected remote application's
        -- exports. Unclassified exports are deliberately kept in their own card.
        local exportKind=current.exportGroups
        -- Four charts per page only when each pane remains comfortably readable.
        local graphColumns=w>=170 and 2 or 1
        local graphRows=(w>=230 and h>=195) and 2 or 1
        local graphSlots=graphColumns*graphRows
        if exportKind=="graphs" then widgets={} end
        if exportKind and type(descriptor.remoteExports)=="table" then
            local exported=descriptor.remoteExports[exportKind] or {}
            local groups,order={},{}
            for _,item in ipairs(exported) do
                if type(item)=="table" and (exportKind~="controls"
                    or (item.remote==true and item.enabled~=false and item.uiHidden~=true)) then
                    local category=type(item.category)=="string" and item.category~=""
                        and item.category~="general" and item.category or "UNCATEGORIZED"
                    if not groups[category] then
                        groups[category]={}
                        order[#order+1]=category
                    end
                    groups[category][#groups[category]+1]=item
                end
            end
            for _,category in ipairs(order) do
                local items=groups[category]
                if exportKind=="graphs" then
                    -- A page never mixes two different graph categories.
                    for first=1,#items,graphSlots do
                        for j=first,math.min(first+graphSlots-1,#items) do
                            local item=items[j]
                            widgets[#widgets+1]={type="graph",id=item.id,
                                label=category.." / "..tostring(item.label or item.id),
                                remoteGraph=item}
                        end
                        if first+graphSlots<=#items or category~=order[#order] then
                            local remaining=graphSlots-math.min(graphSlots,#items-first+1)
                            for _=1,remaining do
                                widgets[#widgets+1]={type="graph-spacer"}
                            end
                        end
                    end
                else
                -- Split long groups to fit the selected card height.
                for start=1,#items,6 do
                    local part={}
                    for j=start,math.min(start+5,#items) do part[#part+1]=items[j] end
                    widgets[#widgets+1]={type="remote-group",label=category,items=part,
                        exportKind=exportKind}
                end
                end
            end
        end
        -- Application controls form a compact toolbar, not giant data cards.
        -- The application decides widget order and which actions exist.
        if #actions>0 then
            local rows=math.ceil(#actions/math.max(1,math.min(4,math.floor((w-12)/65))))
            local slots=math.max(1,math.min(4,math.floor((w-12)/65)))
            local buttonW=math.floor((w-12-4*(slots-1))/slots)
            for i,widget in ipairs(actions) do
                local x=6+((i-1)%slots)*(buttonW+4)
                local y=top+math.floor((i-1)/slots)*13
                local ctrl=controls[widget.id or ""]
                local ready=ctrl and ctrl.monitor==true and ctrl.enabled~=false
                local pending=ready and options.pendingControl==widget.id
                gfx.button(target,hitboxes,x,y,buttonW,11,
                    (pending and "CONFIRM " or "")..(widget.label or (ctrl and ctrl.label) or widget.id),
                    C.panel,ready and "display.control."..widget.id or "display.disabled",
                    nil,C,pending)
            end
            top=top+rows*13+2
        end
        local graphMode=current.id=="graphs" or current.id=="machine_graphs"
        local controlsMode=current.id=="control" or current.id=="machine_controls"
        local autoColumns=graphMode and (w>=150 and 2 or 1) or (w>=160 and 3 or 2)
        local columns=math.max(1,math.min(4,math.floor(tonumber(current.columns) or autoColumns)))
        if exportKind=="graphs" then columns=graphColumns end
        columns=math.min(columns,math.max(1,math.floor((w-12)/42)))
        local preferredHeight=math.max(24,math.floor(tonumber(current.cardHeight) or 52))
        local rowsPerPage=(graphMode and graphRows) or (exportKind=="controls" and 1)
            or math.max(1,math.floor((bottom-top+4)/(preferredHeight+4)))
        local perPage=math.max(1,columns*rowsPerPage)
        local totalPages=math.max(1,math.ceil(#widgets/perPage))
        local viewPage=math.max(1,math.min(totalPages,math.floor(tonumber(options.page) or 1)))
        local first=(viewPage-1)*perPage+1
        local last=math.min(#widgets,first+perPage-1)
        local shown=math.max(1,last-first+1)
        local rows=math.max(1,math.ceil(shown/columns))
        -- Keep a consistent chart height even when the last page has one chart.
        -- A sparse page must not stretch its remaining graph vertically.
        local layoutRows=(exportKind=="graphs") and graphRows or rows
        local gap=4
        local width=math.floor((w-12-gap*(columns-1))/columns)
        local height=math.max(24,math.floor((bottom-top-gap*(layoutRows-1))/layoutRows))
        if tonumber(current.cardHeight) then
            height=math.min(height,math.max(24,math.floor(current.cardHeight)))
        end
        local function valueOf(item,precision)
            if not item then return "--" end
            if type(item.value)=="number" then
                local digits=precision
                if digits==nil then digits=(item.value%1==0) and 0 or 2 end
                digits=math.max(0,math.min(4,math.floor(tonumber(digits) or 0)))
                return string.format("%."..tostring(digits).."f",item.value)
            end
            return val(item.value)
        end
        for i=first,last do
            local widget=widgets[i]
            local n=i-first
            local x=6+(n%columns)*(width+gap)
            local y=top+math.floor(n/columns)*(height+gap)
            if y+height<=bottom+1 then
                if widget.type=="graph-spacer" then
                    -- No frame for an unused graph slot.
                elseif widget.type=="remote-group" then
                    gfx.frame(target,x,y,width,height,C.border)
                    label(target,x+4,y+3,widget.label or "UNCATEGORIZED",width-8,C.accent)
                    local lineY=y+15
                    local maxRows=math.max(0,math.floor((height-19)/10))
                    for j,item in ipairs(widget.items or {}) do
                        if j>maxRows then break end
                        local name=tostring(item.label or item.id or "--")
                        local value
                        if widget.exportKind=="controls" then
                            value=item.enabled==false and "DISABLED"
                                or (item.remote==true and "REMOTE" or "LOCAL")
                        elseif widget.exportKind=="graphs" then
                            local samples=item.samples or {}
                            local recent=samples[#samples]
                            value=recent and val(recent.value) or "--"
                        else
                            value=type(item.value)=="boolean"
                                and (item.value and (item.trueLabel or "ON") or (item.falseLabel or "OFF"))
                                or val(item.value)
                            if item.unit and item.unit~="" then value=value.." "..item.unit end
                        end
                        if widget.exportKind=="controls" then
                            local state=tostring(item.state or ""):lower()
                            local booleanState=(state=="true" or state=="false")
                            if booleanState then
                                value=state=="true" and (item.trueLabel or item.label or "ON")
                                    or (item.falseLabel or item.label or "OFF")
                            else value=item.label or item.id or "CONTROL" end
                            local slot=(i-first)*6+j
                            local buttonId="remote_export_"..slot
                            local ctrl=controls[buttonId]
                            local ready=ctrl and ctrl.monitor==true and ctrl.enabled~=false
                                and item.remote==true and item.enabled~=false
                            local pending=ready and options.pendingControl==buttonId
                            gfx.button(target,hitboxes,x+4,lineY-1,width-8,10,
                                (pending and "CONFIRM " or "")..tostring(value),C.panel,
                                ready and "display.control."..buttonId or "display.disabled",
                                nil,C,pending)
                            lineY=lineY+10
                        else
                        local available=math.max(8,width-8)
                        local valueWidth=math.min(math.floor(available*0.42),#value*4)
                        label(target,x+4,lineY,name,available-valueWidth-4,C.muted)
                        local color=type(item.value)=="boolean"
                            and (item.value and C.ok or C.warn) or C.text
                        label(target,x+width-valueWidth-4,lineY,value,valueWidth,color)
                        lineY=lineY+10
                        end
                    end
                elseif widget.type=="machine-row" then
                    local item=data[widget.id]
                    local name=item and val(item.value) or "--"
                    local select=controls[widget.select or ""]
                    local reboot=controls[widget.reboot or ""]
                    local buttonW=math.min(58,math.max(38,math.floor(width*0.16)))
                    local nameW=math.max(10,width-2*buttonW-22)
                    gfx.frame(target,x,y,width,height,C.border)
                    label(target,x+5,y+math.max(3,math.floor((height-5)/2)),
                        name,nameW,C.text)
                    local by=y+math.max(2,math.floor((height-11)/2))
                    if not widget.hideSelect and widget.select and select
                        and select.monitor==true and select.enabled~=false then
                    gfx.button(target,hitboxes,x+width-2*buttonW-10,by,buttonW,11,
                        "SELECT",C.panel,
                        select and select.monitor==true and select.enabled~=false
                            and "display.control."..widget.select or "display.disabled",
                        nil,C)
                    end
                    if widget.reboot then
                    gfx.button(target,hitboxes,x+width-buttonW-5,by,buttonW,11,
                        "REBOOT",C.panel,
                        reboot and reboot.monitor==true and reboot.enabled~=false
                            and "display.control."..widget.reboot or "display.disabled",
                        nil,C)
                    end
                elseif widget.type=="group" then
                    gfx.frame(target,x,y,width,height,C.border)
                    label(target,x+4,y+3,widget.label or "GROUP",width-8,C.accent)
                    local lineY=y+15
                    local maxRows=math.max(0,math.floor((height-19)/10))
                    for j,item in ipairs(widget.items or {}) do
                        if j>maxRows then break end
                        local id=type(item)=="table" and item.id or item
                        local source=data[id]
                        local name=(type(item)=="table" and item.label) or (source and source.label) or id
                        local precision=type(item)=="table" and item.precision or nil
                        local value=valueOf(source,precision)
                        local available=math.max(8,width-8)
                        local valueWidth=math.min(math.floor(available*0.42),#value*6)
                        label(target,x+4,lineY,tostring(name),available-valueWidth-4,C.muted)
                        label(target,x+width-valueWidth-4,lineY,value,valueWidth,C.text)
                        lineY=lineY+10
                    end
                elseif widget.type=="data" then
                    local item=data[widget.id]
                    gfx.frame(target,x,y,width,height,C.border)
                    label(target,x+4,y+3,widget.label or (item and item.label) or widget.id,width-8,C.accent)
                    label(target,x+4,y+math.max(9,height-9),valueOf(item,widget.precision),width-8,C.text)
                elseif widget.type=="graph" then
                    local item=widget.remoteGraph or graphs[widget.id]
                    gfx.frame(target,x,y,width,height,C.border)
                    label(target,x+4,y+3,widget.label or (item and item.label) or widget.id,width-8,C.accent)
                    local samples=item and item.samples or {}
                    local low,high=tonumber(item and item.min),tonumber(item and item.max)
                    local detectedLow,detectedHigh
                    for _,sample in ipairs(samples) do
                        local v=tonumber(sample.value)
                        if v then
                            detectedLow=math.min(detectedLow or v,v)
                            detectedHigh=math.max(detectedHigh or v,v)
                        end
                    end
                    low=low or detectedLow
                    high=high or detectedHigh
                    local latest=samples[#samples] and tonumber(samples[#samples].value)
                    local graphColor=({colors.yellow,colors.orange,colors.cyan,
                        colors.red,colors.lime,colors.lightBlue})[((i-1)%6)+1]
                    if latest then
                        label(target,x+math.max(5,width-65),y+3,
                            val(latest)..(item.unit and (" "..item.unit) or ""),60,graphColor)
                    end
                    if low and high and #samples>0 then
                        if high<=low then
                            local margin=math.max(math.abs(low)*0.05,1)
                            low=low-margin;high=high+margin
                        end
                        local py=y+14
                        local ph=math.max(2,height-29)
                        local plotX=x+30
                        local plotW=math.max(2,width-35)
                        for tick=0,2 do
                            local yy=py+math.floor(tick*(ph-1)/2)
                            gfx.line(target,plotX,yy,plotX+plotW-1,yy,C.panel)
                            label(target,x+3,yy-2,
                                val(high-(high-low)*tick/2),25,C.muted)
                        end
                        -- CC epoch timestamps use milliseconds; resolution and
                        -- timeWindow are explicitly declared in seconds.
                        local lastTime=tonumber(samples[#samples].timestamp)
                        local span=tonumber(item and item.timeWindow)
                        local grid=tonumber(item and item.resolution)
                        if not span or span<=0 then span=120 end
                        local earliest=lastTime and lastTime-span*1000
                        local function pointX(j)
                            if earliest then
                                local timestamp=tonumber(samples[j].timestamp)
                                if timestamp then
                                    return plotX+math.floor(math.max(0,math.min(1,
                                        (timestamp-earliest)/(span*1000)))*(plotW-1))
                                end
                            end
                            return plotX+math.floor((j-1)*(plotW-1)/math.max(1,#samples-1))
                        end
                        if grid and grid>0 and grid<=span then
                            local steps=math.floor(span/grid)
                            for tick=0,math.min(steps,8) do
                                local seconds=math.floor((span-tick*grid)+0.5)
                                local xx=plotX+math.floor(tick*grid/span*(plotW-1))
                                gfx.line(target,xx,py,xx,py+ph-1,C.panel)
                                label(target,math.max(x+2,math.min(x+width-28,xx-12)),
                                    py+ph+3,"-"..seconds.."s",28,C.muted)
                            end
                        else
                            label(target,plotX,py+ph+3,"-"..math.floor(span).."s",42,C.muted)
                            label(target,x+width-24,py+ph+3,"NOW",22,C.muted)
                        end
                        for j=2,#samples do
                            local va=tonumber(samples[j-1].value)
                            local vb=tonumber(samples[j].value)
                            local t0=tonumber(samples[j-1].timestamp)
                            local t1=tonumber(samples[j].timestamp)
                            if va and vb and (not earliest or
                                (t0 and t1 and t0>=earliest and t1>=earliest)) then
                                local x0,x1=pointX(j-1),pointX(j)
                                local y0=py+ph-1-math.floor(math.max(0,math.min(1,
                                    (va-low)/(high-low)))*(ph-1))
                                local y1=py+ph-1-math.floor(math.max(0,math.min(1,
                                    (vb-low)/(high-low)))*(ph-1))
                                gfx.line(target,x0,y0,x1,y1,graphColor)
                            end
                        end
                    end
                elseif widget.type=="toggle" then
                    local state=data[widget.state]
                    local enabled=state and (state.value==true or state.value==widget.onValue)
                    local id=enabled and widget.off or widget.on
                    local ctrl=controls[id or ""]
                    local title=widget.label or widget.state or "TOGGLE"
                    local ready=ctrl and ctrl.monitor==true and ctrl.enabled~=false
                    local pending=ready and options.pendingControl==id
                    gfx.button(target,hitboxes,x,y,width,height,
                        (pending and "CONFIRM " or "")..title.." "..(enabled and "ON" or "OFF"),
                        enabled and C.ok or C.panel,
                        ready and "display.control."..id or "display.disabled",nil,C,pending)
                    if not ready then hitboxes[#hitboxes]=nil end
                elseif widget.type=="action" then
                    local ctrl=controls[widget.id or ""]
                    local ready=ctrl and ctrl.monitor==true and ctrl.enabled~=false
                    local pending=ready and options.pendingControl==widget.id
                    gfx.button(target,hitboxes,x,y,width,height,
                        (pending and "CONFIRM " or "")..(widget.label or (ctrl and ctrl.label) or widget.id),
                        C.panel,ready and "display.control."..widget.id or "display.disabled",
                        nil,C,pending)
                    if not ready then hitboxes[#hitboxes]=nil end
                end
            end
        end
        -- Application navigation stays at the bottom. Content paging belongs
        -- to the upper subcategory strip on every SDK screen (Master/Pocket).
        local navY=h-13
        local needsPager=totalPages>1 or (type(customNav)=="table" and not exportKind)
        local sideW=needsPager and 27 or 0
        local upperY=17
        local function pageArrow(id,x,labelText)
            gfx.button(target,hitboxes,x,upperY,sideW,10,labelText,
                C.panel,id,nil,C)
        end
        if type(customNav)=="table" and not exportKind then
            for _,edge in ipairs({
                {id=customNav.previous,x=5,label="<"},
                {id=customNav.next,x=w-sideW-5,label=">"}
            }) do
                local ctrl=edge.id and controls[edge.id]
                if ctrl and ctrl.monitor==true and ctrl.enabled~=false then
                    pageArrow("display.control."..edge.id,edge.x,edge.label)
                end
            end
        elseif totalPages>1 then
            if viewPage>1 then pageArrow("display.previous",5,"<") end
            if viewPage<totalPages then pageArrow("display.next",w-sideW-5,">") end
        end
        local tw=(w-12)/math.max(1,#roots)
        for i,v in ipairs(roots) do
            local x=math.floor(6+(i-1)*tw)
            local bw=math.floor(6+i*tw)-x-2
            if bw>=18 then
                gfx.button(target,hitboxes,x,navY,bw,10,v.label,
                    v.id==activeRoot and C.accent or C.panel,
                    "display.view."..v.id,nil,C,v.id==activeRoot)
            end
        end
        if #subtabs>0 then
            local tabs={{id=activeRoot,label=(rootView and (rootView.id=="machines" or rootView.id=="machine")) and "MACHINES" or "DATA"}}
            for _,v in ipairs(subtabs) do tabs[#tabs+1]=v end
            local tabStart=6+sideW
            local tabArea=w-12-2*sideW
            local tabWidth=math.floor(tabArea/#tabs)
            for i,v in ipairs(tabs) do
                local x=tabStart+(i-1)*tabWidth
                local bw=math.min(tabWidth-2,tabStart+tabArea-x-2)
                if v.id==current.id and totalPages>1 then
                    v={id=v.id,label=v.label.." "..viewPage.."/"..totalPages}
                end
                if bw>=18 then
                    gfx.button(target,hitboxes,x,upperY,bw,10,v.label,
                        v.id==current.id and C.accent or C.panel,
                        "display.view."..v.id,nil,C,v.id==current.id)
                end
            end
        elseif needsPager then
            label(target,sideW+9,upperY+2,
                (current.label or current.id).." "..viewPage.."/"..totalPages,
                math.max(0,w-2*sideW-18),C.muted)
        end
        -- A machine/source selector is shared by its parent and every subview.
        -- All buttons and labels are drawn by display; the app declares IDs.
        if type(sourceNav)=="table" then
            local y=30
            local side=math.max(27,math.min(55,math.floor(w/5)))
            local previous=controls[sourceNav.previous or ""]
            local nextControl=controls[sourceNav.next or ""]
            if sourceNav.titleOnly==true then
                local selected=data[sourceNav.data or ""]
                local heading=gfx.fitText(val(selected and selected.value),w-24,1)
                gfx.text(target,math.floor((w-gfx.textWidth(heading,1))/2),y+2,
                    heading,C.accent,1)
            else
            if previous and previous.monitor==true and previous.enabled~=false then
                gfx.button(target,hitboxes,5,y,side,11,"< SOURCE",C.panel,
                    "display.control."..sourceNav.previous,nil,C)
            end
            if nextControl and nextControl.monitor==true and nextControl.enabled~=false then
                gfx.button(target,hitboxes,w-side-5,y,side,11,"SOURCE >",C.panel,
                    "display.control."..sourceNav.next,nil,C)
            end
            local selected=data[sourceNav.data or ""]
            label(target,side+10,y+2,val(selected and selected.value),
                math.max(0,w-2*side-20),C.text)
            end
        end
        if options.graphicsAvailable~=false then
            gfx.button(target,hitboxes,w-55,2,50,10,
                "TEXT MODE",C.panel,"display.toggle",nil,C)
        end
        local out={}
        for _,hit in ipairs(hitboxes) do
            out[#out+1]={x1=hit.x1,y1=hit.y1,x2=hit.x2,y2=hit.y2,id=hit.action}
        end
        return {ok=true,backend="ccgraphics",page=viewPage,pageCount=totalPages,
            view=current.id,width=w,height=h,hitboxes=out}
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
