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
local function usage()
    print("Usage:")
    print("  authctl allow <machineKey>")
    print("  authctl client")
    print("  authctl revoke <machineKey>")
    print("  authctl status")
    print("Allow trusts all exported remote controls for a signed peer.")
    print("The SAME shared secret must be entered on both computers.")
end
if command=="status" then
    local policy=load()
    local peers=policy.peers or {}
    print("Trusted machines:")
    for machine,peer in pairs(peers) do
        print(machine.." : "..((peer.enabled and peer.allControls) and "ALLOWED" or "RESTRICTED"))
    end
    print("Client: "..(policy.client and policy.client.enabled and "CONFIGURED" or "OFF"))
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
