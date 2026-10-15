-- Read-only SDK service status adapter.
local M={}
function M.status(name)
    if type(name)~="string" or name=="" then return nil,"name required" end
    local snap=require("lib.runtime").snapshot()
    local entries=type(snap.entries)=="table" and snap.entries or {}
    local item=entries["app:"..name] or entries["module:"..name]
        or entries["capability:"..name]
    if not item then return {status="inactive",detail="not reported"} end
    return {status=item.status or "unknown",detail=item.detail,
        updatedAt=item.webUpdatedAt or item.updatedAt}
end
return M
