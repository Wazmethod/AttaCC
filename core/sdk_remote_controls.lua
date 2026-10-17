-- Common Pocket/Master control lookup.
-- Remote display buttons send an exported control ID, never a screen slot.
local M={}

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
