-- Symmetric SHA-256 message authentication for AttaCC SDK command envelopes.
-- Secrets and ACLs are configured locally, never distributed in packages.
local M={}
local function hexToRaw(hex)
    return (hex:gsub("%x%x",function(pair) return string.char(tonumber(pair,16)) end))
end
local function sha(raw)
    if not textutils or type(textutils.sha256)~="function" then
        return nil,"textutils.sha256 unavailable"
    end
    local ok,value=pcall(textutils.sha256,raw)
    if not ok or type(value)~="string" or not value:match("^%x+$") or #value~=64 then
        return nil,"invalid sha256 result"
    end
    return value:lower()
end
local function hmac(secret,message)
    if type(secret)~="string" or #secret<32 then return nil,"secret requires at least 32 bytes" end
    if #secret>64 then
        local digest,err=sha(secret)
        if not digest then return nil,err end
        secret=hexToRaw(digest)
    end
    secret=secret..string.rep("\0",64-#secret)
    local ipad,opad={},{}
    for i=1,64 do
        local b=secret:byte(i)
        ipad[i]=string.char(bit32.bxor(b,0x36))
        opad[i]=string.char(bit32.bxor(b,0x5c))
    end
    local inside,err=sha(table.concat(ipad)..message)
    if not inside then return nil,err end
    return sha(table.concat(opad)..hexToRaw(inside))
end
-- Stable typed serialization rejects unsupported or recursive arguments.
local function canonical(value,depth,seen)
    if depth>8 then error("arguments too deep") end
    local kind=type(value)
    if kind=="nil" then return "null" end
    if kind=="boolean" then return value and "true" or "false" end
    if kind=="number" then
        if value~=value or value==math.huge or value==-math.huge then error("invalid number") end
        return string.format("%.17g",value)
    end
    if kind=="string" then return textutils.serializeJSON(value) end
    if kind~="table" then error("unsupported value") end
    if seen[value] then error("cyclic arguments") end
    seen[value]=true
    local keys, count = {}, 0
    for k in pairs(value) do
        if type(k)~="string" or not k:match("^[%w_%-]+$") then error("invalid argument key") end
        count=count+1
        if count>64 then error("too many arguments") end
        keys[#keys+1]=k
    end
    table.sort(keys)
    local entries={}
    for _,k in ipairs(keys) do
        entries[#entries+1]=canonical(k,depth+1,seen)..":"..canonical(value[k],depth+1,seen)
    end
    seen[value]=nil
    return "{"..table.concat(entries,",").."}"
end
function M.payload(message)
    if type(message)~="table" or type(message.args)~="table" then return nil,"invalid envelope" end
    for _,field in ipairs({"app","control","origin","target","network","id"}) do
        if type(message[field])~="string" or message[field]=="" or #message[field]>128 then
            return nil,"invalid "..field
        end
    end
    if type(message.timestamp)~="number" or message.timestamp%1~=0 then return nil,"invalid timestamp" end
    local ok, body=pcall(function()
        return canonical({
            type=message.type,app=message.app,control=message.control,
            origin=message.origin,target=message.target,network=message.network,
            id=message.id,timestamp=message.timestamp,args=message.args
        },0,{})
    end)
    if not ok then return nil,tostring(body) end
    if #body>8192 then return nil,"message too large" end
    return body
end
local function equal(a,b)
    if type(a)~="string" or type(b)~="string" or #a~=#b then return false end
    local diff=0
    for i=1,#a do diff=bit32.bor(diff,bit32.bxor(a:byte(i),b:byte(i))) end
    return diff==0
end
function M.sign(message,secret)
    local payload,err=M.payload(message)
    if not payload then return nil,err end
    return hmac(secret,payload)
end
function M.authorize(message,policy)
    if type(policy)~="table" or type(policy.peers)~="table" then return false,"authorization not configured" end
    local peer=policy.peers[message.origin]
    if type(peer)~="table" or peer.enabled~=true then return false,"unknown or disabled peer" end
    if type(peer.key)~="string" or #peer.key<32 then return false,"invalid peer secret" end
    if type(peer.controls)~="table" or peer.controls[message.control]~=true then
        return false,"control forbidden"
    end
    if type(message.auth)~="table" or message.auth.version~=1
        or type(message.auth.signature)~="string" then return false,"signature missing" end
    local signature,err=M.sign(message,peer.key)
    if not signature then return false,err end
    if not equal(signature,message.auth.signature:lower()) then return false,"invalid signature" end
    return true
end
-- Protect ACKs as well: otherwise an observer can forge success/failure.
function M.signAck(ack,secret)
    if type(ack)~="table" then return nil,"invalid ACK" end
    for _,field in ipairs({"id","app","control","origin","target","network"}) do
        if type(ack[field])~="string" or ack[field]=="" then return nil,"invalid ACK "..field end
    end
    if type(ack.ok)~="boolean" or type(ack.timestamp)~="number" then return nil,"invalid ACK status" end
    local ok,payload=pcall(canonical,{
        type=ack.type,id=ack.id,app=ack.app,control=ack.control,
        origin=ack.origin,target=ack.target,network=ack.network,
        ok=ack.ok,error=ack.error or "",timestamp=ack.timestamp
    },0,{})
    if not ok then return nil,tostring(payload) end
    return hmac(secret,payload)
end
function M.verifyAck(ack,secret)
    if type(ack)~="table" or type(ack.auth)~="table" or ack.auth.version~=1 then
        return false,"unsigned ACK"
    end
    local signature,err=M.signAck(ack,secret)
    if not signature then return false,err end
    return equal(signature,ack.auth.signature),"invalid ACK signature"
end
function M.load(path)
    path=path or "/etc/sdk-auth.lua"
    if not fs.exists(path) then return nil,"SDK authorization not configured" end
    local ok,result=pcall(dofile,path)
    if not ok or type(result)~="table" then return nil,"invalid SDK authorization config" end
    return result
end
return M
