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
            elseif kind == "data" or kind == "control" or kind == "graph" then
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
        for _, id in ipairs(selected.controls or {}) do top[#top+1]={type="control",id=id} end
    end
    if #top > 0 or #groups == 0 then
        table.insert(groups,1,{label=selected.label or selected.id,items=top})
    end

    local result = {}
    local available = math.max(1, height-4)
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
    local pages, err, view=M.pages(descriptor, options.view, w, h)
    if err then put(target,1,1,err,w);return {ok=false,warning=err,hitboxes={}} end
    local index=math.max(1,math.min(#pages,math.floor(tonumber(options.page) or 1)))
    local data=indexed(descriptor.data)
    local controls=indexed(descriptor.controls)
    local hits={}
    put(target,1,1,(descriptor.title or descriptor.id or "AttaCC").." / "..(pages[index].label or view.label or view.id),w)
    put(target,1,2,string.rep("-",w),w)
    local y=3
    for _,item in ipairs(pages[index].items) do
        local ref=(item.type=="control" and controls or data)[item.id or ""]
        local label=item.label or (ref and ref.label) or item.id or ""
        if item.type=="header" then
            put(target,1,y,"["..label.."]",w)
        elseif item.type=="control" then
            put(target,1,y,"[ "..label.." ]",w)
            if ref then hits[#hits+1]={x1=1,x2=math.min(w,#label+4),y=y,id=item.id} end
        elseif item.type=="graph" then
            put(target,1,y,label.." [graph: view on Web]",w)
        else
            local value=ref and ref.value
            put(target,1,y,label..": "..tostring(value == nil and "—" or value)..(ref and ref.unit and (" "..ref.unit) or ""),w)
        end
        y=y+1
    end
    put(target,1,h,"Page "..index.."/"..#pages.."  < > navigate",w)
    return {ok=true,page=index,pageCount=#pages,width=w,height=h,hitboxes=hits,view=view.id}
end

function M.hit(result,x,y)
    for _,area in ipairs(result and result.hitboxes or {}) do
        if y==area.y and x>=area.x1 and x<=area.x2 then return area.id end
    end
    return nil
end

return M
