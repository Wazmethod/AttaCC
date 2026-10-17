-- Machine-wide SDK administration policy, independent from the active app.
-- No file means remote system administration is denied.
local M={}
local path="/etc/attacc/system.lua"
local defaults={admin={enabled=false,actions={
    reboot=false,package_update=false,package_configure=false
}},display={monitorName="",textScale=0.5,touchProfile="normal",
    touchFlipX=false,touchFlipY=false,touchInsetX=0,touchInsetY=0}}
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
    local display=policy.display
    if display~=nil and type(display)~="table" then return nil,"invalid system display settings" end
    display=display or {}
    result.display={}
    for key,default in pairs(defaults.display) do
        local value=display[key]
        if value==nil then value=default end
        if type(value)~=type(default) then return nil,"invalid display."..key end
        if key=="textScale" and (value~=value or value<0.5 or value>5 or value*2%1~=0) then
            return nil,"invalid display.textScale (expected CC:Tweaked scale: 0.5 to 5 in 0.5 steps)"
        end
        if key=="touchProfile" and (#value>64 or value:find("[%c]")) then
            return nil,"invalid display.touchProfile"
        end
        if (key=="touchInsetX" or key=="touchInsetY") and (value~=value or value%1~=0 or math.abs(value)>64) then
            return nil,"invalid display."..key.." (integer from -64 to 64 required)"
        end
        if key=="monitorName" and (#value>128 or value:find("[%c]")) then
            return nil,"invalid display.monitorName"
        end
        result.display[key]=value
    end
    return result
end
return M
