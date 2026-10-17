-- Generic text-mode declarative view renderer for AttaCC SDK v1.1.
-- No app-specific UI dependencies. Uses CraftOS term/monitor methods.
local M = {}
local MIN_W, MIN_H = 18, 7

local function put(t, x, y, text, width, color)
    local w,h = t.getSize()
    if y < 1 or y > h or x > w then return end
    text = tostring(text or "")
    width = math.max(0, math.min(width or #text, w-x+1))
    if width == 0 then return end
    t.setCursorPos(x,y)
    if color and t.setTextColor then t.setTextColor(color) end
    t.write(text:sub(1,width))
end

-- Share transient feedback with CC:Graphics (notably touch confirmations).
-- A toast covers the secondary footer, so that row must not remain clickable.
local function drawToast(target, options, w, h, hits)
    local toast=options and options.toast
    if h<3 or type(toast)~="table" or not toast.message then return end
    for i=#hits,1,-1 do
        if hits[i].y==h-1 then table.remove(hits,i) end
    end
    local color=toast.kind=="error" and colors.red
        or toast.kind=="success" and colors.lime or colors.yellow
    put(target,1,h-1,string.rep(" ",w),w)
    put(target,1,h-1,tostring(toast.message),w,color)
end

local function flatten(items, out, depth)
    out = out or {}
    depth = depth or 0
    if depth > 12 then return out end
    for _, item in ipairs(items or {}) do
        if type(item) == "table" then
            local kind = item.type or item.kind or "section"
            if kind == "section" or kind == "group" then
                out[#out+1] = {type="header",label=item.label or item.title or ""}
                flatten(item.children or item.items, out, depth+1)
            elseif kind == "data" or kind == "control" or kind == "graph" or kind == "banner" then
                out[#out+1] = {type=kind,id=item.id or item.key,label=item.label}
            elseif kind == "action" then
                out[#out+1] = {type="control",id=item.id,label=item.label}
            elseif kind == "machine-row" then
                out[#out+1] = {type="machine-row",id=item.id,select=item.select,label=item.label}
            elseif kind == "toggle" then
                out[#out+1] = {type="toggle",state=item.state,
                    on=item.on,off=item.off,onValue=item.onValue,label=item.label}
            elseif kind == "page" then
                -- A page is a navigation boundary; its children are not merged into the parent page.
            end
        elseif type(item) == "string" then
            out[#out+1] = {type="data",id=item}
        end
    end
    return out
end

function M.pages(descriptor, viewId, width, height)
    local selected
    for _, v in ipairs(descriptor.views or {}) do
        if v.id == viewId then selected = v; break end
    end
    selected = selected or (descriptor.views or {})[1]
    if not selected then return {}, "no views" end

    local groups = {}
    local top = {}
    for _, node in ipairs(selected.children or {}) do
        if type(node) == "table" and (node.type == "page" or node.kind == "page") then
            if #top > 0 then groups[#groups+1] = {label=selected.label or selected.id, items=top}; top={} end
            local nested = {}
            flatten(node.children or node.items, nested)
            groups[#groups+1] = {label=node.label or node.title or node.id or "Page",items=nested}
        else
            local items = flatten({node})
            for _, item in ipairs(items) do top[#top+1] = item end
        end
    end
    if type(selected.children) ~= "table" then
        for _,widget in ipairs(flatten(selected.widgets or {})) do
            if widget.type~="machine-row" or selected.dynamicRows~=true then
                top[#top+1]=widget
            else
                local record
                for _,item in ipairs(descriptor.data or {}) do
                    if item.id==widget.id then record=item;break end
                end
                if record and record.value~=nil and record.value~="--" then
                    top[#top+1]=widget
                end
            end
        end
        for _, id in ipairs(selected.data or {}) do top[#top+1]={type="data",id=id} end
        for _, id in ipairs(selected.graphs or {}) do top[#top+1]={type="graph",id=id} end
        for _, id in ipairs(selected.controls or {}) do top[#top+1]={type="control",id=id} end
    end
    -- Text mode must show the same exported groups as CC:Graphics.
    local exportKind=selected.exportGroups
    local exports=type(descriptor.remoteExports)=="table"
        and descriptor.remoteExports[exportKind] or nil
    if type(exports)=="table" then
        local byCategory,order={},{}
        for _,item in ipairs(exports) do
            if type(item)=="table" and type(item.id)=="string"
                and (exportKind~="controls" or (
                    item.uiHidden~=true and item.enabled~=false and
                    (selected.localExports==true and item.monitor==true
                     or selected.localExports~=true and item.remote==true))) then
                local category=type(item.category)=="string" and item.category~=""
                    and item.category or "general"
                if not byCategory[category] then
                    byCategory[category]={}
                    order[#order+1]=category
                end
                byCategory[category][#byCategory[category]+1]={
                    type="export-"..exportKind,id=item.id,item=item
                }
            end
        end
        for _,category in ipairs(order) do
            -- Tiny monitors have one content row: the page title already
            -- carries the category, so do not waste a page on its header.
            local items={}
            if height>=7 then items[1]={type="header",label=category} end
            for _,item in ipairs(byCategory[category]) do
                items[#items+1]=item
            end
            groups[#groups+1]={label=category,items=items}
        end
    end
    if #top > 0 or #groups == 0 then
        table.insert(groups,1,{label=selected.label or selected.id,items=top})
    end

    local result = {}
    local available = math.max(1, height-5)
    for _, group in ipairs(groups) do
        local page = {}
        for _, leaf in ipairs(group.items) do
            if #page >= available then
                result[#result+1] = {label=group.label,items=page}
                page = {}
            end
            page[#page+1]=leaf
        end
        if #page>0 or #group.items==0 then
            result[#result+1] = {label=group.label,items=page}
        end
    end
    return result,nil,selected
end

local function indexed(items)
    local out={}
    for _, item in ipairs(items or {}) do if item.id then out[item.id]=item end end
    return out
end

-- Compact native text layout for small external monitors (including 3x1).
-- Never present a fatal resolution error when at least two lines fit.
local function compact(target, descriptor, options, w, h)
    if w<8 or h<2 then
        put(target,1,1,"AttaCC",w)
        return {ok=false,warning="resolution_too_low",width=w,height=h,hitboxes={}}
    end
    local view
    for _,candidate in ipairs(descriptor.views or {}) do
        if candidate.id==options.view then view=candidate;break end
    end
    view=view or (descriptor.views or {})[1]
    if not view then
        put(target,1,1,"No view",w)
        return {ok=false,warning="no_view",hitboxes={}}
    end
    local entries={}
    local data=indexed(descriptor.data)
    local controls=indexed(descriptor.controls)
    local pageGroups=M.pages(descriptor,view.id,w,h)
    for _,group in ipairs(pageGroups) do
        for _,leaf in ipairs(group.items) do
            if leaf.type=="header" then
                entries[#entries+1]={header=tostring(leaf.label or group.label)}
            elseif leaf.type=="export-data" or leaf.type=="export-graphs" then
                local entry=leaf.item
                local value=entry.value
                if leaf.type=="export-graphs" then
                    local samples=type(entry.samples)=="table" and entry.samples or {}
                    local recent=samples[#samples]
                    value=type(recent)=="table" and recent.value or nil
                elseif type(value)=="boolean" then
                    value=value and (entry.trueLabel or "ON") or (entry.falseLabel or "OFF")
                end
                entries[#entries+1]={label=entry.label or entry.id,
                    value=value,unit=entry.unit}
            elseif leaf.type=="export-controls" then
                local entry=leaf.item
                local localControl=view.localExports==true
                local ready=entry.enabled~=false
                    and (localControl and entry.monitor==true
                        or not localControl and options.remoteControlReady==true)
                local state=tostring(entry.state or ""):lower()
                local label=state=="true" and (entry.trueLabel or entry.label)
                    or state=="false" and (entry.falseLabel or entry.label)
                    or entry.label or entry.id
                entries[#entries+1]={label=label,enabled=ready,
                    control=localControl and "display.control."..entry.id
                        or "display.control.remote."..entry.id}
            elseif leaf.type=="toggle" then
                local state=data[leaf.state or ""]
                local engaged=state and (state.value==true
                    or (leaf.onValue~=nil and state.value==leaf.onValue))
                local action=engaged and leaf.off or leaf.on
                local control=controls[action or ""]
                entries[#entries+1]={label=(leaf.label or leaf.state or "TOGGLE")
                    ..(engaged and " [ON]" or " [OFF]"),
                    enabled=control and control.monitor==true and control.enabled~=false,
                    control=action and "display.control."..action or nil}
            elseif leaf.type=="machine-row" then
                local record=data[leaf.id]
                local ctrl=controls[leaf.select or ""]
                entries[#entries+1]={label=tostring(record and record.value or "--"),
                    enabled=ctrl and ctrl.enabled~=false,
                    control=leaf.select and "display.control."..leaf.select or nil}
            elseif leaf.type=="control" then
                local ctrl=controls[leaf.id]
                if ctrl then
                    entries[#entries+1]={label=leaf.label or ctrl.label or leaf.id,
                        enabled=ctrl.enabled~=false,
                        control="display.control."..leaf.id}
                end
            elseif leaf.type=="data" then
                local item=data[leaf.id]
                entries[#entries+1]={label=leaf.label or (item and item.label) or leaf.id,
                    value=item and item.value,unit=item and item.unit}
            elseif leaf.type=="banner" then
                local banner=indexed(descriptor.banners)[leaf.id]
                if banner then
                    entries[#entries+1]={label=leaf.label or banner.label or leaf.id,
                        value=banner.value}
                end
            elseif leaf.type=="graph" then
                local graph=indexed(descriptor.graphs)[leaf.id]
                local samples=graph and graph.samples or {}
                local recent=samples[#samples]
                entries[#entries+1]={label=leaf.label or (graph and graph.label) or leaf.id,
                    value=type(recent)=="table" and recent.value or nil,
                    unit=graph and graph.unit}
            end
        end
    end
    local perPage=math.max(1,h-3)
    local total=math.max(1,math.ceil(#entries/perPage))
    local page=math.max(1,math.min(total,math.floor(tonumber(options.page) or 1)))
    local hits={}
    put(target,1,1,(view.label or descriptor.title or "AttaCC"),w,colors.cyan)
    for i=1,perPage do
        local item=entries[(page-1)*perPage+i]
        if item then
            local y=i+1
            if item.header then
                put(target,1,y,"["..item.header.."]",w,colors.yellow)
            elseif item.control then
                put(target,1,y,(item.enabled and "> " or "- ")..tostring(item.label),w,
                    item.enabled and colors.lime or colors.gray)
                if item.enabled then
                    hits[#hits+1]={id=item.control,x1=1,x2=w,y=y}
                end
            else
                local value=item.value==nil and "--" or tostring(item.value)
                put(target,1,y,item.label..": "..value..
                    (item.unit and (" "..item.unit) or ""),w,colors.white)
            end
        end
    end
    if h>=3 then
        local footer=tostring(page).."/"..tostring(total)
        put(target,math.max(1,math.floor((w-#footer)/2)+1),h,footer,w,colors.lightGray)
        if total>1 then
            put(target,1,h,"PREV",w,colors.yellow)
            put(target,math.max(1,w-3),h,"NEXT",w,colors.yellow)
            hits[#hits+1]={id="display.previous",x1=1,x2=math.min(w,4),y=h}
            hits[#hits+1]={id="display.next",x1=math.max(1,w-3),x2=w,y=h}
        end
    end
    local navigation=view.sourceNavigation
    if not navigation and view.parent then
        for _,parent in ipairs(descriptor.views or {}) do
            if parent.id==view.parent then navigation=parent.sourceNavigation;break end
        end
    end
    if h>=4 and type(navigation)=="table" then
        local label=data[navigation.data or ""]
        put(target,1,h-1,tostring(label and label.value or "--"),w,colors.cyan)
        if navigation.previous and controls[navigation.previous]
            and controls[navigation.previous].enabled~=false then
            put(target,1,h-1,"<",1,colors.yellow)
            hits[#hits+1]={id="display.control."..navigation.previous,
                x1=1,x2=1,y=h-1}
        end
        if navigation.next and controls[navigation.next]
            and controls[navigation.next].enabled~=false then
            put(target,w,h-1,">",1,colors.yellow)
            hits[#hits+1]={id="display.control."..navigation.next,
                x1=w,x2=w,y=h-1}
        end
    elseif h>=4 and options.graphicsAvailable==true then
        put(target,1,h-1,"GRAPHICS MODE",w,colors.cyan)
        hits[#hits+1]={id="display.toggle",x1=1,x2=math.min(w,13),y=h-1}
    end
    if #(descriptor.views or {})>1 then
        local views=descriptor.views
        local at=1
        for i,candidate in ipairs(views) do
            if candidate.id==view.id then at=i;break end
        end
        put(target,1,1,"<",1,colors.yellow)
        put(target,w,1,">",1,colors.yellow)
        hits[#hits+1]={id="display.view."..views[(at-2+#views)%#views+1].id,
            x1=1,x2=1,y=1}
        hits[#hits+1]={id="display.view."..views[at%#views+1].id,
            x1=w,x2=w,y=1}
    end
    drawToast(target,options,w,h,hits)
    return {ok=true,backend="text",graphicsAvailable=options.graphicsAvailable==true,
        compact=true,page=page,pageCount=total,
        width=w,height=h,hitboxes=hits,view=view.id}
end

-- A view-independent read-only status page, declared by the application.
-- Compact and full-size monitors use the same paginated presentation.
local function summary(target,descriptor,options,w,h)
    local spec=descriptor.textSummary
    local data=indexed(descriptor.data)
    local lines={}
    for _,section in ipairs(spec.sections or {}) do
        lines[#lines+1]={header=section.label or ""}
        for _,field in ipairs(section.fields or {}) do
            local item=data[field.id]
            local value=item and item.value
            if field.boolean and type(value)=="boolean" then
                value=value and "ON" or "OFF"
            elseif type(value)=="number" then
                value=string.format("%."..math.max(0,math.min(5,field.precision or 2)).."f",value)
            end
            if value==nil then value="--" end
            local unit=item and item.unit or nil
            local line=(field.label or (item and item.label) or field.id)..": "..tostring(value)
            if unit and not field.boolean then line=line.." "..unit end
            lines[#lines+1]={value=line}
        end
    end
    local hasToggle=options.graphicsAvailable==true
    local footerRows=hasToggle and 2 or 1
    local capacity=math.max(1,h-footerRows-1)
    local pageCount=math.max(1,math.ceil(#lines/capacity))
    local page=math.max(1,math.min(pageCount,math.floor(tonumber(options.page) or 1)))
    local hits={}
    put(target,1,1,spec.title or descriptor.title or "STATUS",w,colors.cyan)
    for i=1,capacity do
        local line=lines[(page-1)*capacity+i]
        if line then
            if line.header then
                put(target,1,i+1,"["..line.header.."]",w,colors.yellow)
            else
                put(target,1,i+1,line.value,w,colors.white)
            end
        end
    end
    if hasToggle then
        put(target,1,h-1,"GRAPHICS MODE",w,colors.lime)
        hits[#hits+1]={x1=1,x2=math.min(w,13),y=h-1,id="display.toggle"}
    end
    local footer="STATUS "..page.."/"..pageCount
    local center=math.max(1,math.floor((w-#footer)/2)+1)
    put(target,center,h,footer,w,colors.lightGray)
    if pageCount>1 then
        put(target,1,h,"PREV",w,colors.yellow)
        put(target,math.max(1,w-3),h,"NEXT",w,colors.yellow)
        hits[#hits+1]={x1=1,x2=math.min(4,w),y=h,id="display.previous"}
        hits[#hits+1]={x1=math.max(1,w-3),x2=w,y=h,id="display.next"}
    end
    drawToast(target,options,w,h,hits)
    return {ok=true,backend="text",graphicsAvailable=options.graphicsAvailable==true,
        compact=w<MIN_W or h<MIN_H,
        page=page,pageCount=pageCount,width=w,height=h,hitboxes=hits,
        view=options.view}
end

function M.render(target, descriptor, options)
    options=options or {}
    target=target or term.current()
    local w,h=target.getSize()
    local selectedView
    for _, view in ipairs(descriptor.views or {}) do
        if view.id == options.view then selectedView=view; break end
    end
    selectedView=selectedView or (descriptor.views or {})[1] or {}
    local minW=tonumber(options.minWidth or selectedView.minWidth) or MIN_W
    local minH=tonumber(options.minHeight or selectedView.minHeight) or MIN_H
    if target.setBackgroundColor then target.setBackgroundColor(colors.black) end
    if target.setTextColor then target.setTextColor(colors.white) end
    target.clear()
    if options.viewMode=="views" and type(descriptor.textSummary)=="table" then
        return summary(target,descriptor,options,w,h)
    end
    if w < minW or h < minH then
        return compact(target,descriptor,options,w,h)
    end
    local views=descriptor.views or {}
    local selectedId=options.view or (views[1] and views[1].id)
    local technicalId
    for _,v in ipairs(views) do if (v.category=="maintenance" or v.category=="technical") and v.persistent then technicalId=v.id; break end end
    if options.view=="__technical" and technicalId then selectedId=technicalId end
    options.view=selectedId
    local pages, err, view=M.pages(descriptor, options.view, w, h)
    if err then put(target,1,1,err,w);return {ok=false,warning=err,hitboxes={}} end
    local index=math.max(1,math.min(#pages,math.floor(tonumber(options.page) or 1)))
    local data=indexed(descriptor.data)
    local controls=indexed(descriptor.controls)
    local graphs=indexed(descriptor.graphs)
    local banners=indexed(descriptor.banners)
    local hits={}
    local graphicsAvailable = options.graphicsAvailable == true
    local backend = options.backend or "text"
    put(target,1,1,(descriptor.title or descriptor.id or "AttaCC").." / "..(pages[index].label or view.label or view.id),w,colors.cyan)
    -- Single-character arrows switch declarative views on text-only displays.
    if #views>1 then
        local at=1
        for i,candidate in ipairs(views) do
            if candidate.id==view.id then at=i;break end
        end
        local previous=views[(at-2+#views)%#views+1]
        local following=views[at%#views+1]
        put(target,1,1,"<",1,colors.yellow)
        put(target,w,1,">",1,colors.yellow)
        hits[#hits+1]={x1=1,x2=1,y=1,id="display.view."..previous.id}
        hits[#hits+1]={x1=w,x2=w,y=1,id="display.view."..following.id}
    end
    local navigation=view.sourceNavigation
    if not navigation and view.parent then
        for _,parent in ipairs(views) do
            if parent.id==view.parent then navigation=parent.sourceNavigation;break end
        end
    end
    if type(navigation)=="table" then
        local selected=data[navigation.data or ""]
        local label=tostring(selected and selected.value or "--")
        put(target,1,2,label,w,colors.cyan)
        if navigation.previous and controls[navigation.previous]
            and controls[navigation.previous].enabled~=false then
            put(target,1,2,"<",1,colors.yellow)
            hits[#hits+1]={x1=1,x2=1,y=2,
                id="display.control."..navigation.previous}
        end
        if navigation.next and controls[navigation.next]
            and controls[navigation.next].enabled~=false then
            put(target,w,2,">",1,colors.yellow)
            hits[#hits+1]={x1=w,x2=w,y=2,
                id="display.control."..navigation.next}
        end
    else
        put(target,1,2,string.rep("-",w),w)
    end
    local y=3
    for _,item in ipairs(pages[index].items) do
        local ref=(item.type=="control" and controls or data)[item.id or ""]
        local label=item.label or (ref and ref.label) or item.id or ""
        if item.type=="header" then
            put(target,1,y,"["..label.."]",w)
        elseif item.type=="control" then
            local builtIn = item.id == "display.toggle"
            if not builtIn or graphicsAvailable then
                local disabled = ref and ref.enabled == false
                local shown = disabled and ("( "..label.." - unavailable )") or ("[ "..label.." ]")
                put(target,1,y,shown,w,disabled and colors.gray or colors.lime)
                if (ref and not disabled) or builtIn then
                    hits[#hits+1]={x1=1,x2=math.min(w,#shown),y=y,
                        id=builtIn and item.id or "display.control."..item.id}
                end
            end
        elseif item.type=="toggle" then
            local state=data[item.state or ""]
            local engaged=state and (state.value==true
                or (item.onValue~=nil and state.value==item.onValue))
            local action=engaged and item.off or item.on
            local control=controls[action or ""]
            local ready=control and control.monitor==true and control.enabled~=false
            local pending=ready and options.pendingControl==action
            local label=(item.label or item.state or "TOGGLE")
                ..(engaged and " [ON]" or " [OFF]")
            local shown=(ready and "[ " or "( ")
                ..(pending and "CONFIRM " or "")..label
                ..(ready and " ]" or " )")
            put(target,1,y,shown,w,ready and colors.lime or colors.gray)
            if ready then
                hits[#hits+1]={x1=1,x2=math.min(w,#shown),y=y,
                    id="display.control."..action}
            end
        elseif item.type=="machine-row" then
            local machine=data[item.id or ""]
            local selected=controls[item.select or ""]
            local name=machine and machine.value or "--"
            local ready=selected and selected.enabled~=false
            local shown=(ready and "> " or "- ")..tostring(name)
            put(target,1,y,shown,w,ready and colors.lime or colors.white)
            if ready then
                hits[#hits+1]={x1=1,x2=w,y=y,
                    id="display.control."..item.select}
            end
        elseif item.type=="export-data" then
            local entry=item.item
            local value=entry.value
            if type(value)=="boolean" then
                value=value and (entry.trueLabel or "ON") or (entry.falseLabel or "OFF")
            end
            put(target,1,y,tostring(entry.label or entry.id)..": "..
                tostring(value==nil and "--" or value)..
                (entry.unit and (" "..tostring(entry.unit)) or ""),w,colors.white)
        elseif item.type=="export-graphs" then
            local entry=item.item
            local samples=type(entry.samples)=="table" and entry.samples or {}
            local latest=samples[#samples]
            put(target,1,y,tostring(entry.label or entry.id)..": "..
                tostring(type(latest)=="table" and latest.value or "--")..
                (entry.unit and (" "..tostring(entry.unit)) or ""),w,colors.white)
        elseif item.type=="export-controls" then
            local entry=item.item
            local state=tostring(entry.state or ""):lower()
            local label=state=="true" and (entry.trueLabel or entry.label)
                or state=="false" and (entry.falseLabel or entry.label)
                or entry.label or entry.id
            local remote=view.localExports~=true
            local ready=entry.enabled~=false
                and (remote and options.remoteControlReady==true
                    or not remote and entry.monitor==true)
            local id=remote and "display.control.remote."..entry.id
                or "display.control."..entry.id
            local pending=options.pendingControl==(remote and "remote."..entry.id or entry.id)
            local shown=(ready and "> " or "- ")..
                (pending and "CONFIRM " or "")..tostring(label)
            put(target,1,y,shown,w,ready and colors.lime or colors.gray)
            if ready then
                hits[#hits+1]={x1=1,x2=w,y=y,id=id}
            end
        elseif item.type=="graph" then
            local graph=graphs[item.id or ""]
            local samples=graph and graph.samples or {}
            local last=samples[#samples]
            local value=last and last.value or 0
            local lo=tonumber(graph and graph.min) or 0
            local hi=tonumber(graph and graph.max) or lo
            if not (graph and graph.max) then
                for _, sample in ipairs(samples) do hi=math.max(hi,sample.value or lo) end
            end
            if hi<=lo then hi=lo+1 end
            local width=math.max(3,math.min(16,w-2))
            local fraction=math.max(0,math.min(1,(value-lo)/(hi-lo)))
            local filled=math.floor(fraction*width+0.5)
            local bar="["..string.rep("#",filled)..string.rep("-",width-filled).."]"
            put(target,1,y,label.." "..bar.." "..tostring(value),w)
        elseif item.type=="banner" then
            local banner=banners[item.id or ""]
            if banner then
                local message=tostring(banner.value == nil and "" or banner.value)
                local offset=math.floor(tonumber(options.scrollOffset) or 0)
                if banner.scroll ~= false and #message>w then
                    local cycle=message.."   "
                    local shift=offset % #cycle
                    message=cycle:sub(shift+1)..cycle:sub(1,shift)
                    while #message<w do message=message..cycle end
                end
                put(target,1,y,message,w)
            end
        else
            local value=ref and ref.value
            put(target,1,y,label..": "..tostring(value == nil and "—" or value)..(ref and ref.unit and (" "..ref.unit) or ""),w)
        end
        y=y+1
    end
    if graphicsAvailable then
        put(target,1,h-1,"[ "..(backend=="text" and "GRAPHICS" or "TEXT").." MODE ]",w)
        hits[#hits+1]={x1=1,x2=math.min(w,18),y=h-1,id="display.toggle"}
    end
    local footer="Page "..index.."/"..#pages
    local maintenance=view.category=="maintenance" or view.category=="technical"
    if maintenance then
        local label="[ BACK TO APP ]"
        put(target,math.max(1,w-#label+1),h,label,w)
        hits[#hits+1]={x1=math.max(1,w-#label+1),x2=w,y=h,id="display.home"}
    elseif technicalId then
        local label="[ MAINT ]"
        put(target,math.max(1,w-#label+1),h,label,w)
        hits[#hits+1]={x1=math.max(1,w-#label+1),x2=w,y=h,id="display.maintenance"}
    end
    put(target,1,h,footer,w)
    if #pages>1 then
        local prevX=math.max(1,w-15)
        local nextX=math.max(1,w-7)
        put(target,prevX,h,"PREV",w,colors.yellow)
        put(target,nextX,h,"NEXT",w,colors.yellow)
        hits[#hits+1]={x1=prevX,x2=math.min(w,prevX+3),y=h,id="display.previous"}
        hits[#hits+1]={x1=nextX,x2=math.min(w,nextX+3),y=h,id="display.next"}
    end
    drawToast(target,options,w,h,hits)
    return {ok=true,backend="text",graphicsAvailable=graphicsAvailable,
        page=index,pageCount=#pages,width=w,height=h,hitboxes=hits,view=view.id}
end

function M.hit(result,x,y)
    for _,area in ipairs(result and result.hitboxes or {}) do
        if y==area.y and x>=area.x1 and x<=area.x2 then return area.id end
    end
    return nil
end

return M
