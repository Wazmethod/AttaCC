-- SDK Web command gate. Web servers must be authenticated at the transport boundary.
-- This component never signs commands itself: sdk_remote owns signatures and ACKs.
local M={}
function M.new(app,options)
    options=options or {}
    local seen={}
    local now=function() return os.epoch("utc") end
    local self={}
    function self:execute(request,callback)
        if type(callback)~="function" then return false,"callback required" end
        if options.enabled~=true then return false,"web commands disabled" end
        if type(request)~="table" or request.type~="attacc.sdk.web.command.v1"
            then return false,"invalid request type" end
        local id=request.id
        if type(id)~="string" or #id<1 or #id>128
            or not id:match("^[%w_.%-]+$") then return false,"invalid request id" end
        if seen[id] then return false,"duplicate request" end
        for _,field in ipairs({"target","app","control"}) do
            if type(request[field])~="string" or #request[field]<1
                or #request[field]>128 then return false,"invalid "..field end
        end
        if type(request.args)~="table" then return false,"invalid arguments" end
        if type(request.timestamp)~="number"
            or math.abs(now()-request.timestamp)>10000 then
            return false,"expired request"
        end
        if type(request.network)~="string" or request.network~=options.network then
            return false,"wrong network"
        end
        local rules=options.rules
        local appRules=type(rules)=="table" and rules[request.app]
        local targets=type(appRules)=="table" and appRules.targets
        local targetRules=type(targets)=="table" and targets[request.target]
        local controls=type(targetRules)=="table" and targetRules.controls
        if type(controls)~="table" or controls[request.control]~=true then
            return false,"command not permitted"
        end
        seen[id]=now()
        local ok,cmdId=app:remoteCommand(request.target,request.app,request.control,
            request.args,function(success,reason,_,ack)
                callback(success,reason,ack)
            end)
        if not ok then return false,cmdId end
        return true,cmdId
    end
    function self:tick()
        local t=now()
        for id,at in pairs(seen) do if t-at>60000 then seen[id]=nil end end
    end
    return self
end
return M
