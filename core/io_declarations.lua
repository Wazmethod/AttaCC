-- Persistent declaration registry consumed by ioctl independently of app process.
local M={}
local path="/var/lib/attacc/io-requirements.json"
local function read()
    if not fs.exists(path) then return {} end
    local h=fs.open(path,"r")
    if not h then return {} end
    local raw=h.readAll()
    h.close()
    local ok,value=pcall(textutils.unserializeJSON,raw)
    return ok and type(value)=="table" and value or {}
end
function M.all()
    local combined={}
    for app,roles in pairs(read()) do
        if type(roles)=="table" then
            for key,req in pairs(roles) do
                if type(req)=="table" then combined[app.."."..key]=req end
            end
        end
    end
    return combined
end
function M.publish(app,roles)
    if type(app)~="string" or not app:match("^[%w_%-]+$") then return false,"invalid app id" end
    if type(roles)~="table" then return false,"invalid roles" end
    local checked={}
    for id,req in pairs(roles) do
        if type(id)~="string" or not id:match("^[%w_%-]+$") or type(req)~="table"
           or type(req.type)~="string" or req.type=="" then return false,"invalid requirement" end
        checked[id]={type=req.type,required=req.required==true,
            direction=req.direction or "input",description=req.label or req.description or id,
            invert=req.invert == true,readOutput=req.readOutput == true}
    end
    local all=read()
    all[app]=checked
    if not fs.exists("/var/lib/attacc") then fs.makeDir("/var/lib/attacc") end
    local temp=path..".new"
    local h=fs.open(temp,"w")
    if not h then return false,"cannot write requirements" end
    h.write(textutils.serializeJSON(all))
    h.close()
    if fs.exists(path) then fs.delete(path) end
    fs.move(temp,path)
    return true
end
return M
