local args = { ... }
if not args[1] or args[1] == "help" or args[1] == "--help" then
    print("webbridgectl configure")
    print("Configure WebSocket URL, machine token, retries and network labels.")
    return
end
if args[1] ~= "configure" then error("unknown command") end

local FILE = "/etc/webbridge.lua"
local SEEN_FILE = "/run/attacc/webbridge-networks.json"

local function quote(v) return string.format("%q", tostring(v or "")) end

local function serialize(value, indent)
    indent = indent or ""
    local t=type(value)
    if t=="string" then return quote(value) end
    if t=="number" or t=="boolean" then return tostring(value) end
    if t~="table" then return "nil" end
    local lines={"{"}; local child=indent.."    "
    local keys={}
    for k in pairs(value) do table.insert(keys,k) end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,k in ipairs(keys) do
        local key=tostring(k):match("^[%a_][%w_]*$") and tostring(k)
            or ("["..quote(k).."]")
        table.insert(lines,child..key.." = "..serialize(value[k],child)..",")
    end
    table.insert(lines,indent.."}")
    return table.concat(lines,"\n")
end

local function readLua()
    if not fs.exists(FILE) then return nil,"missing "..FILE end
    local ok,v=pcall(dofile,FILE)
    if not ok or type(v)~="table" then return nil,"invalid "..FILE end
    return v
end

local function writeLua(v)
    local tmp=FILE..".new"
    local h=fs.open(tmp,"w")
    if not h then return false,"cannot write "..tmp end
    h.write("return "..serialize(v).."\n"); h.close()
    if fs.exists(FILE) then fs.delete(FILE) end
    fs.move(tmp,FILE)
    return true
end

local function seenNetworks()
    if not fs.exists(SEEN_FILE) then return {} end
    local h=fs.open(SEEN_FILE,"r"); if not h then return {} end
    local raw=h.readAll(); h.close()
    local ok,v=pcall(textutils.unserializeJSON,raw)
    return ok and type(v)=="table" and v or {}
end

local cfg,err=readLua()
if not cfg then
    if fs.exists(FILE) then error(err) end
    cfg={ url="", machineToken="", retrySeconds=3, networkLabels={} }
end
cfg.networkLabels=type(cfg.networkLabels)=="table" and cfg.networkLabels or {}

print("ATTACC WEBBRIDGE CONFIGURATION")
print("Web backend must be running and its MACHINE_TOKEN must match.")
print("Example: ws://192.168.1.50:8080/ws/machine")
print("For HTTPS, use wss://your-domain/ws/machine")
write("WebSocket URL ["..tostring(cfg.url or "").."]: ")
local url=read()
if url~="" then cfg.url=url end
if type(cfg.url)~="string" or not cfg.url:match("^wss?://.+/ws/machine$") then
    error("WebSocket URL must start with ws:// or wss:// and end with /ws/machine")
end
write("Machine token ["..((cfg.machineToken and cfg.machineToken~="") and "configured" or "missing").."] (blank=keep): ")
local token=read()
if token~="" then cfg.machineToken=token end
if type(cfg.machineToken)~="string" or cfg.machineToken=="" or cfg.machineToken=="CHANGE_ME" then
    error("Set the MACHINE_TOKEN from the Web backend before saving")
end
write("Reconnect delay seconds ["..tostring(cfg.retrySeconds or 3).."]: ")
local retry=read()
if retry~="" then
    local n=tonumber(retry)
    if not n or n<1 or n>120 then error("Retry delay must be 1..120 seconds") end
    cfg.retrySeconds=n
end

local networks=seenNetworks()
for id in pairs(cfg.networkLabels) do
    local found=false
    for _,n in ipairs(networks) do if n==id then found=true break end end
    if not found then table.insert(networks,id) end
end
table.sort(networks)

print("ATTACC WEBBRIDGE / NETWORK LABELS")
print("")
if #networks==0 then print("No networks observed yet.") end
for _,id in ipairs(networks) do
    local current=cfg.networkLabels[id] or id
    write(id.." ["..current.."]: ")
    local value=read()
    if value~="" then
        if value=="-" or value==id then cfg.networkLabels[id]=nil
        else cfg.networkLabels[id]=value end
    end
end

local ok,writeErr=writeLua(cfg)
if not ok then error(writeErr) end
print("")
print("Saved. Restart Master to apply URL or token changes.")
print("WebBridge starts automatically when "..FILE.." exists.")
