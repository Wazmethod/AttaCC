-- Public application facade helpers. Internal AttaCC modules remain private.
local M={}
local function configTable()
    local ok,cfg=pcall(require,"lib.config")
    return ok and cfg or {}
end
local function walk(root,path)
    local node=root
    for part in path:gmatch("[^%.]+") do
        if type(node)~="table" then return nil end
        node=node[part]
    end
    return node
end
function M.configure(app,defaults)
    if type(defaults)~="table" then error("config defaults must be a table",3) end
    app.defaults=defaults
    return app
end
function M.value(app,path,fallback)
    if type(path)~="string" or path=="" then error("config path required",3) end
    local override=walk(configTable(),path)
    if override~=nil then return override end
    local def=walk(app.defaults or {},path)
    if def~=nil then return def end
    return fallback
end
function M.requirements(app,items)
    if items == nil then
        local loaded,err=require("lib.io_catalog").forApp(app.id)
        if not loaded then error(err,3) end
        items=loaded
    end
    if type(items)~="table" then error("requirements table expected",3) end
    for role,spec in pairs(items) do
        if type(role)~="string" or type(spec)~="table" then error("invalid requirement",3) end
        app:io(role,{type=spec.type,direction=spec.direction,required=spec.required,
            label=spec.description or spec.label,invert=spec.invert,readOutput=spec.readOutput})
    end
    return app
end
function M.device(app,role)
    local declaration=(app.hardware or {})[role]
    if not declaration then return nil,"undeclared I/O role: "..tostring(role) end
    local obj={}
    function obj:call(method,...) return app:call(role,method,...) end
    function obj:read(fallback) return app:read(role,fallback) end
    function obj:write(value,fallback) return app:write(role,value,fallback) end
    function obj:available()
        local device,err=require("lib.io_registry").resolve(app.id.."."..role,declaration)
        return device~=nil,err
    end
    return obj
end
function M.dependency(app,id)
    if type(id)~="string" or not id:match("^[%w_.%-]+$") then
        error("invalid dependency id",3)
    end
    app.dependencies=app.dependencies or {}
    app.dependencies[id]=true
    return app
end
function M.checkDependencies(app)
    -- Independent from application code: reserved IDs map to installed capabilities.
    local known={
        ["core.runtime"]="lib/runtime.lua",
        ["module.network"]="lib/network.lua",
        ["module.display"]="lib/display_api.lua",
        ["module.storage-client"]="lib/storage_client.lua",
    }
    local missing={}
    for name in pairs(app.dependencies or {}) do
        local path=known[name]
        if not path or not fs.exists(path) then missing[#missing+1]=name end
    end
    table.sort(missing)
    return #missing==0,missing
end
return M
