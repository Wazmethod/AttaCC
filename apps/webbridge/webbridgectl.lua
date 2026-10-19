local args = { ... }
local AUTOSTART="/etc/attacc/services.lua"
local function services()
    if not fs.exists(AUTOSTART) then return {} end
    local ok,value=pcall(dofile,AUTOSTART)
    if not ok or type(value)~="table" then
        error("Invalid SDK service configuration: "..AUTOSTART)
    end
    return value
end
if not args[1] or args[1] == "help" then
    print("webbridgectl status")
    print("webbridgectl configure")
    print("webbridgectl enable")
    print("webbridgectl disable")
    print("Configure a standalone WebBridge or its reboot autostart.")
    return
end
if args[1]=="enable" or args[1]=="disable" then
    local enabled=args[1]=="enable"
    if enabled and not fs.exists("apps/webbridge/main.lua") then
        error("Install app.webbridge first")
    end
    local list=services()
    list.webbridge=enabled
    local dir=fs.getDir(AUTOSTART)
    if not fs.exists(dir) then fs.makeDir(dir) end
    local tmp=AUTOSTART..".new"
    local h=fs.open(tmp,"w")
    if not h then error("Unable to write "..tmp) end
    h.write("return "..textutils.serialize(list).."\n")
    h.close()
    if fs.exists(AUTOSTART) then fs.delete(AUTOSTART) end
    fs.move(tmp,AUTOSTART)
    print("WebBridge autostart: "..(enabled and "enabled" or "disabled"))
    print("Reboot to apply. On a dedicated CC, use preset.webbridge instead.")
    return
end
if args[1] == "status" then
    print("Autostart: "..(services().webbridge==true and "enabled" or "disabled"))
    if not fs.exists("/etc/webbridge.lua") then
        print("WebBridge: NOT CONFIGURED")
        print("Run webbridgectl configure")
        return
    end
    local ok,cfg=pcall(dofile,"/etc/webbridge.lua")
    if not ok or type(cfg)~="table" then
        printError("WebBridge: INVALID CONFIGURATION")
        return
    end
    print("WebBridge URL: "..tostring(cfg.url or "not set"))
    print("Machine token: "..(type(cfg.machineToken)=="string" and
        cfg.machineToken~="" and "configured" or "missing"))
    local loaded,runtime=pcall(require,"lib.runtime")
    if loaded and type(runtime.snapshot)=="function" then
        local state=runtime.snapshot()
        local entry=state.entries and state.entries["bridge:connection"]
        print("Connection: "..tostring(entry and entry.status or "not started"))
        if entry and entry.detail then print("Detail: "..tostring(entry.detail)) end
    else
        print("Connection: unknown (runtime unavailable)")
    end
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
print("Saved. Restart the WebBridge app to apply URL or token changes.")
print("Run pkgctl run webbridge, or activate preset.webbridge on a dedicated CC.")
