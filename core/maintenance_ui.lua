-- AttaCC terminal maintenance UI: application-owned data, SDK-owned layout.
-- Renders in a native CraftOS terminal tab; no monitor or graphics dependency.
local M={}
local function text(value) return tostring(value == nil and "-" or value) end
local function draw(t,x,y,value,color)
    local w,h=t.getSize()
    if y<1 or y>h or x>w then return end
    t.setCursorPos(x,y)
    if t.setTextColor and color then t.setTextColor(color) end
    t.write(text(value):sub(1,math.max(0,w-x+1)))
end
local function statusColor(value)
    local s=text(value):lower()
    if s=="active" or s=="ready" or s=="running" or s=="ok" then return colors.lime end
    if s=="missing" or s=="error" or s=="failed" or s=="inactive" then return colors.red end
    return colors.orange
end
function M.render(t,definition,options)
    t=t or term.current()
    options=options or {}
    local w,h=t.getSize()
    if t.setBackgroundColor then t.setBackgroundColor(colors.black) end
    if t.setTextColor then t.setTextColor(colors.white) end
    t.clear()
    local hits={}
    if w<24 or h<9 then
        draw(t,1,1,"ATTACC / MAINTENANCE",colors.yellow)
        draw(t,1,2,"Terminal too small",colors.orange)
        draw(t,1,3,w.."x"..h.." (min 24x9)",colors.lightGray)
        return {ok=false,warning="resolution_too_low",hitboxes={}}
    end
    draw(t,2,1,"ATTACC / "..text(definition.title or "MAINTENANCE"),colors.cyan)
    local lines={}
    local function section(label) lines[#lines+1]={kind="header",text=label} end
    local function entry(label,value,detail,required)
        lines[#lines+1]={kind="entry",label=text(label),value=text(value),detail=detail,required=required}
    end
    section("STATUS")
    for _,item in ipairs(definition.status or {}) do
        entry(item.label or item.id,item.value,item.detail)
    end
    section("TOOLS")
    local tools=definition.tools or {}
    if #tools==0 then lines[#lines+1]={kind="message",text="No technical actions"} end
    for _,item in ipairs(tools) do
        lines[#lines+1]={kind="tool",id=item.id,label=text(item.label or item.id),enabled=item.enabled~=false}
    end
    section("REQUIREMENTS")
    for _,item in ipairs(definition.requirements or {}) do
        entry(item.label or item.id,item.status or "UNKNOWN",
            item.detail,item.required)
    end
    section("RECENT")
    for _,item in ipairs(definition.logs or {}) do
        lines[#lines+1]={kind="message",text=text(item.message or item),level=item.level}
    end
    local pageSize=math.max(1,h-4)
    local pageCount=math.max(1,math.ceil(#lines/pageSize))
    local page=math.max(1,math.min(pageCount,math.floor(tonumber(options.page) or 1)))
    local start=(page-1)*pageSize+1
    for i=start,math.min(#lines,start+pageSize-1) do
        local item=lines[i]
        local y=i-start+3
        if item.kind=="header" then
            draw(t,2,y,item.text,colors.yellow)
        elseif item.kind=="entry" then
            draw(t,2,y,item.label,colors.lightGray)
            draw(t,math.min(w,21),y,item.value,statusColor(item.value))
            local note=item.detail and (" "..text(item.detail)) or ""
            if item.required~=nil then note=note..(item.required and " [required]" or " [optional]") end
            draw(t,math.min(w,math.max(28,23+#item.value)),y,note,colors.gray)
        elseif item.kind=="tool" then
            local label="[ "..item.label.." ]"
            draw(t,2,y,label,item.enabled and colors.white or colors.gray)
            if item.enabled then
                hits[#hits+1]={id=item.id,x1=2,x2=math.min(w,#label+1),y=y}
            end
        else
            draw(t,2,y,item.text,item.level=="error" and colors.red or colors.lightGray)
        end
    end
    draw(t,2,h,"PAGE "..page.."/"..pageCount.."  [PREV] [NEXT]",colors.gray)
    if pageCount>1 then
        hits[#hits+1]={id="maintenance.previous",x1=math.min(w,17),x2=math.min(w,22),y=h}
        hits[#hits+1]={id="maintenance.next",x1=math.min(w,24),x2=math.min(w,29),y=h}
    end
    return {ok=true,page=page,pageCount=pageCount,hitboxes=hits}
end
function M.hit(result,x,y)
    for _,hit in ipairs(result and result.hitboxes or {}) do
        if hit.y==y and x>=hit.x1 and x<=hit.x2 then return hit.id end
    end
    return nil
end
return M
