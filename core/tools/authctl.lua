-- AttaCC SDK trust management. Machine-wide permissions, signed transport.
-- A machine key is an identifier, NOT a secret.
local args={...}
local command,key=args[1],args[2]
local path="/etc/sdk-auth.lua"
local function load()
    if not fs.exists(path) then return {} end
    local ok,value=pcall(dofile,path)
    if not ok or type(value)~="table" then
        error("Invalid "..path.."; refusing to overwrite",0)
    end
    return value
end
local function save(policy)
    fs.makeDir("/etc")
    local temp=path..".new"
    local handle,err=fs.open(temp,"w")
    if not handle then error(err or "cannot write authorization",0) end
    handle.write("return "..textutils.serialize(policy).."\n")
    handle.close()
    local backup=path..".bak"
    if fs.exists(backup) then fs.delete(backup) end
    if fs.exists(path) then fs.move(path,backup) end
    local ok,reason=pcall(fs.move,temp,path)
    if not ok then
        if fs.exists(backup) then fs.move(backup,path) end
        error(reason,0)
    end
    if fs.exists(backup) then fs.delete(backup) end
end
local function validKey(s)
    return type(s)=="string" and #s>=1 and #s<=128
        and s:match("^[%w_:%.%-]+$")~=nil
end
local function safeSecret(secret,reveal)
    if type(secret)~="string" or secret=="" then return "(missing)" end
    return reveal and secret or ("[hidden, "..#secret.." chars]")
end
local function showClient(client,reveal)
    if type(client)~="table" then print("Client: NOT CONFIGURED");return end
    print("Client:")
    print("  enabled: "..tostring(client.enabled==true))
    print("  origin:  "..tostring(client.origin or "(unset)"))
    print("  secret:  "..safeSecret(client.secret,reveal))
end
local function showPeer(machine,peer,reveal)
    if type(peer)~="table" then print("Peer not configured: "..machine);return end
    print("Peer: "..machine)
    print("  enabled:     "..tostring(peer.enabled==true))
    print("  allControls: "..tostring(peer.allControls==true))
    if type(peer.controls)=="table" then
        local names={}
        for name,allowed in pairs(peer.controls) do
            if allowed==true then names[#names+1]=name end
        end
        table.sort(names)
        print("  legacy ACL:  "..(#names>0 and table.concat(names,", ") or "(none)"))
    end
    print("  secret:      "..safeSecret(peer.key,reveal))
end
local function usage()
    print("Usage:")
    print("  authctl list                    All local trust configuration")
    print("  authctl show client             Show local signed-command client")
    print("  authctl show <machineKey>      Show authorized peer")
    print("  authctl show client --reveal    Show client secret (private!)")
    print("  authctl show <machineKey> --reveal")
    print("  authctl allow <machineKey>     Create or replace peer trust")
    print("  authctl client                  Create or replace local client")
    print("  authctl revoke <machineKey>    Remove peer trust")
    print("  authctl status                  Brief status (legacy)")
    print("Only signed commands/ACKs require trust. Never publish a secret.")
    print("Use a distinct shared secret per client. Restart apps after changes.")
end
if command=="list" or command=="status" then
    local policy=load()
    showClient(policy.client,false)
    local peers=type(policy.peers)=="table" and policy.peers or {}
    local names={}
    for machine in pairs(peers) do names[#names+1]=machine end
    table.sort(names)
    print("Authorized peers: "..#names)
    for _,machine in ipairs(names) do showPeer(machine,peers[machine],false) end
elseif command=="show" then
    if not key then usage();return end
    local reveal=args[3]=="--reveal"
    if args[3] and not reveal then error("Unknown option: "..tostring(args[3]),0) end
    local policy=load()
    if reveal then
        print("WARNING: the secret grants command authority; keep it private.")
    end
    if key=="client" then showClient(policy.client,reveal)
    elseif validKey(key) then
        showPeer(key,type(policy.peers)=="table" and policy.peers[key],reveal)
    else error("Invalid machine key",0) end
elseif command=="allow" or command=="client" then
    if command=="allow" and not validKey(key) then error("Invalid machine key",0) end
    local identity=require("lib.machine").get()
    print("Local identity: "..tostring(identity.key))
    if command=="client" then print("Configuring this machine as a signed command client")
    else print("Allowing signed requests from: "..key) end
    write("Shared secret (32+ characters): ")
    local secret=read("*")
    if type(secret)~="string" or #secret<32 then error("Secret must have at least 32 characters",0) end
    local policy=load()
    if command=="allow" then
        policy.peers=policy.peers or {}
        policy.peers[key]={enabled=true,key=secret,allControls=true}
    else
        policy.client={enabled=true,origin=identity.key,secret=secret}
    end
    save(policy)
    print("Authorization saved. Restart the SDK application to apply.")
elseif command=="revoke" then
    if not validKey(key) then error("Invalid machine key",0) end
    local policy=load()
    if type(policy.peers)=="table" then policy.peers[key]=nil end
    save(policy)
    print("Peer revoked: "..key)
else usage() end
