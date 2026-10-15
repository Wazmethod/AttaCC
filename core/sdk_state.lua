-- AttaCC SDK-owned persistent application state.
local M={}
local function path(id,key)
    assert(type(id)=="string" and id:match("^[%w_%-]+$"),"invalid app ID")
    assert(type(key)=="string" and key:match("^[%w_%-]+$"),"invalid state key")
    return "/var/lib/attacc/apps/"..id.."/"..key..".json"
end
function M.read(id,key)
    local file=path(id,key)
    if not fs.exists(file) then return nil,"missing" end
    local h=fs.open(file,"r")
    if not h then return nil,"cannot open persistent state" end
    local raw=h.readAll()
    h.close()
    local ok,data=pcall(textutils.unserializeJSON,raw)
    if not ok or type(data)~="table" then return nil,"invalid persistent state" end
    return data
end
function M.write(id,key,data)
    if type(data)~="table" then return false,"persistent state must be a table" end
    local ok,raw=pcall(textutils.serializeJSON,data)
    if not ok or type(raw)~="string" then return false,"cannot encode persistent state" end
    local file=path(id,key)
    local dir=fs.getDir(file)
    if not fs.exists(dir) then fs.makeDir(dir) end
    local tmp=file..".new"
    local h=fs.open(tmp,"w")
    if not h then return false,"cannot open temporary state file" end
    h.write(raw)
    h.close()
    local backup=file..".bak"
    if fs.exists(backup) then fs.delete(backup) end
    if fs.exists(file) then fs.move(file,backup) end
    local moved,err=pcall(fs.move,tmp,file)
    if not moved then
        if fs.exists(backup) then fs.move(backup,file) end
        return false,tostring(err)
    end
    if fs.exists(backup) then fs.delete(backup) end
    return true
end
return M
