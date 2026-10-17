-- Shared remote export selection for Pocket and Master.
-- Display position is never a security authority: the command must be
-- revalidated against the current source descriptor before dispatch.
local M={}
function M.cards(controls)
    local groups,order={},{}
    for _,item in ipairs(controls or {}) do
        if item.remote==true and item.enabled~=false and item.uiHidden~=true then
            local category=type(item.category)=="string" and item.category~=""
                and item.category~="general" and item.category or "UNCATEGORIZED"
            if not groups[category] then
                groups[category]={}
                order[#order+1]=category
            end
            groups[category][#groups[category]+1]=item
        end
    end
    local cards={}
    for _,category in ipairs(order) do
        local items=groups[category]
        for first=1,#items,6 do
            local card={}
            for i=first,math.min(first+5,#items) do card[#card+1]=items[i] end
            cards[#cards+1]=card
        end
    end
    return cards
end
function M.resolve(controls,slot)
    if type(slot)~="number" or slot%1~=0 or slot<1 then
        return nil,"invalid control slot"
    end
    local cards=M.cards(controls)
    local card=cards[math.floor((slot-1)/6)+1]
    local selected=card and card[(slot-1)%6+1]
    if not selected then return nil,"control unavailable" end
    local state=tostring(selected.state or ""):lower()
    local command=selected.toggle==true and selected.id
        or ((state=="true" and selected.trueControl)
            or (state=="false" and selected.falseControl)
            or selected.id)
    for _,item in ipairs(controls or {}) do
        if item.id==command and item.remote==true and item.enabled~=false then
            return {control=command,id=selected.id,category=selected.category}
        end
    end
    return nil,"target command not exported"
end
function M.byId(controls,id)
    if type(id)~="string" or not id:match("^[%w_%-]+$") then
        return nil,"invalid control ID"
    end
    local selected
    for _,item in ipairs(controls or {}) do
        if item.id==id and item.remote==true and item.enabled~=false
            and item.uiHidden~=true then
            selected=item
            break
        end
    end
    if not selected then return nil,"control not exported" end
    local state=tostring(selected.state or ""):lower()
    local command=selected.toggle==true and selected.id
        or ((state=="true" and selected.trueControl)
            or (state=="false" and selected.falseControl)
            or selected.id)
    for _,item in ipairs(controls or {}) do
        if item.id==command and item.remote==true and item.enabled~=false then
            return command
        end
    end
    return nil,"target command not exported"
end
return M
