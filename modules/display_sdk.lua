-- Generic text-mode declarative view renderer for AttaCC SDK v1.1.
-- No app-specific UI dependencies. Uses CraftOS term/monitor methods.
local M = {}
local MIN_W, MIN_H = 18, 7

local function put(t, x, y, text, width)
    local w,h = t.getSize()
    if y < 1 or y > h or x > w then return end
    text = tostring(text or "")
    width = math.max(0, math.min(width or #text, w-x+1))
    if width == 0 then return end
    t.setCursorPos(x,y)
    t.write(text:sub(1,width))
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
        for _, id in ipairs(selected.data or {}) do top[#top+1]={type="data",id=id} end
        for _, id in ipairs(selected.graphs or {}) do top[#top+1]={type="graph",id=id} end
        for _, id in ipairs(selected.controls or {}) do top[#top+1]={type="control",id=id} end
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
    if w < minW or h < minH then
        local note="Display too small"
        put(target,1,1,note,w)
        put(target,1,math.min(2,h),w.."x"..h.." - min "..minW.."x"..minH,w)
        put(target,1,math.min(3,h),"Increase monitor size",w)
        return {ok=false,warning="resolution_too_low",width=w,height=h,minWidth=minW,minHeight=minH,hitboxes={}}
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
    put(target,1,1,(descriptor.title or descriptor.id or "AttaCC").." / "..(pages[index].label or view.label or view.id),w)
    put(target,1,2,string.rep("-",w),w)
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
                put(target,1,y,shown,w)
                if (ref and not disabled) or builtIn then
                    hits[#hits+1]={x1=1,x2=math.min(w,#shown),y=y,id=item.id}
                end
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
        local left=math.max(1,math.floor(w/3))
        hits[#hits+1]={x1=1,x2=left,y=h,id="display.previous"}
        hits[#hits+1]={x1=left+1,x2=math.min(w,left*2),y=h,id="display.next"}
    end
    return {ok=true,page=index,pageCount=#pages,width=w,height=h,hitboxes=hits,view=view.id}
end

function M.hit(result,x,y)
    for _,area in ipairs(result and result.hitboxes or {}) do
        if y==area.y and x>=area.x1 and x<=area.x2 then return area.id end
    end
    return nil
end

return M
