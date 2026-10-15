-- Discover app-owned requirements before the application is started.
local M={}
local function valid(id)
    return type(id)=="string" and id:match("^[%w_%-]+$")~=nil
end
local function load(path)
    if not fs.exists(path) or fs.isDir(path) then return nil end
    local ok, result=pcall(dofile,path)
    if ok and type(result)=="table" then return result end
    return nil
end
function M.forApp(id)
    if not valid(id) then return nil,"invalid application id" end
    local roles=load(fs.combine("apps",fs.combine(id,"requirements.lua")))
        or load(fs.combine("lib","attacc_requirements_"..id..".lua"))
    if not roles then return nil,"requirements not installed for "..id end
    return roles
end
function M.all()
    local result={}
    local ids={}
    if fs.exists("apps") and fs.isDir("apps") then
        for _,id in ipairs(fs.list("apps")) do
            if valid(id) and fs.isDir(fs.combine("apps",id)) then ids[id]=true end
        end
    end
    if fs.exists("lib") and fs.isDir("lib") then
        for _,file in ipairs(fs.list("lib")) do
            local id=file:match("^attacc_requirements_([%w_%-]+)%.lua$")
            if id then ids[id]=true end
        end
    end
    for id in pairs(ids) do
        local roles=M.forApp(id)
        if roles then
            for role,spec in pairs(roles) do
                if valid(role) and type(spec)=="table" and type(spec.type)=="string"
                    and spec.type~="" then result[id.."."..role]=spec end
            end
        end
    end
    return result
end
return M
