-- AttaCC application loader: namespaced relative modules and one public SDK.
local M={}
local function valid(id) return type(id)=="string" and id:match("^[%w_%-]+$")~=nil end
local function appPath(id,relative)
    return fs.combine(fs.combine("apps",id),relative)
end
function M.load(id)
    if not valid(id) then return nil,"invalid application ID" end
    local path=appPath(id,"main.lua")
    if not fs.exists(path) or fs.isDir(path) then return nil,"application entry missing: "..path end
    local sdk=require("lib.attacc")
    local cache={}
    local loading={}
    local function appEnvironment(localRequire)
        return setmetatable({require=localRequire},{__index=_G})
    end
    local function localRequire(name)
        if type(name)~="string" or name=="" or name:sub(1,1)=="."
            or name:sub(-1)=="." or name:find("..",1,true)
            or name:find("[^%w_%.]") then
            error("invalid local module name",2)
        end
        if cache[name]~=nil then return cache[name] end
        if loading[name] then error("circular app module: "..name,2) end
        local relative=name:gsub("%.","/")..".lua"
        local file=appPath(id,relative)
        if not fs.exists(file) or fs.isDir(file) then error("app module unavailable: "..name,2) end
        loading[name]=true
        local module,err=loadfile(file,"t",appEnvironment(function(request)
            if request=="lib.attacc" then return sdk end
            return localRequire(request)
        end))
        if not module then loading[name]=nil; error(err,2) end
        local ok,result=pcall(module)
        loading[name]=nil
        if not ok then error(result,2) end
        cache[name]=result==nil and true or result
        return cache[name]
    end
    local ok,result=pcall(function()
        local entry,err=loadfile(path,"t",appEnvironment(function(name)
            if name=="lib.attacc" then return sdk end
            return localRequire(name)
        end))
        if not entry then error(err) end
        return entry()
    end)
    if not ok then return nil,tostring(result) end
    return result
end
return M
