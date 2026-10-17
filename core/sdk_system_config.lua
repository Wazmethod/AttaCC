-- Machine-wide SDK administration policy, independent from the active app.
-- No file means remote system administration is denied.
local M={}
local path="/etc/attacc/system.lua"
local defaults={admin={enabled=false,actions={
    reboot=false,package_update=false,package_configure=false
}}}
function M.defaults() return defaults end
function M.load()
    if not fs.exists(path) then return defaults end
    local ok,policy=pcall(dofile,path)
    if not ok or type(policy)~="table" then
        return nil,"invalid system configuration: "..path
    end
    if policy.admin~=nil and type(policy.admin)~="table" then
        return nil,"invalid system admin settings"
    end
    local admin=policy.admin or {}
    if admin.enabled~=nil and type(admin.enabled)~="boolean" then
        return nil,"invalid admin.enabled"
    end
    if admin.actions~=nil and type(admin.actions)~="table" then
        return nil,"invalid admin.actions"
    end
    local actions=admin.actions or {}
    local result={admin={enabled=admin.enabled==true,actions={}}}
    for _,name in ipairs({"reboot","package_update","package_configure"}) do
        if actions[name]~=nil and type(actions[name])~="boolean" then
            return nil,"invalid admin.actions."..name
        end
        result.admin.actions[name]=actions[name]==true
    end
    return result
end
return M
