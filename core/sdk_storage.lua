-- Native SDK storage service: requests are signed SDK controls, not raw modem frames.
local M={}
local actions={ping=true,namespaces=true,list=true,get=true,set=true,delete=true}
local function valid(value,max)
    return type(value)=="string" and #value>0 and #value<=max
        and value:match("^[%w_.:%-]+$")~=nil
end
function M.install(app,options)
    options=options or {}
    local enabled=options.enabled==true
    local backend
    app:control("storage_request",{
        label="Storage request",remote=true,monitor=false,
        enabled=function() return enabled end,
        run=function(request)
            if not enabled then return false,"storage service disabled" end
            if type(request)~="table" or not actions[request.action] then
                return false,"invalid storage action"
            end
            if request.action~="ping" and request.action~="namespaces"
                and not valid(request.namespace,64) then
                return false,"invalid namespace"
            end
            if (request.action=="get" or request.action=="set" or request.action=="delete")
                and not valid(request.key,128) then
                return false,"invalid key"
            end
            local permissions=options.actions
            if type(permissions)~="table" or permissions[request.action]~=true then
                return false,"storage action denied"
            end
            if not backend then
                backend=require("lib.storage_backend").new(options.backendConfig or {})
            end
            local result,err
            local action=request.action
            if action=="ping" then result=backend:ping()
            elseif action=="namespaces" then result,err=backend:namespaces()
            elseif action=="list" then result,err=backend:list(request.namespace)
            elseif action=="get" then result,err=backend:get(request.namespace,request.key)
            elseif action=="set" then
                result,err=backend:set(request.namespace,request.key,request.value,
                    app.id)
            elseif action=="delete" then result,err=backend:delete(request.namespace,request.key)
            end
            if err then return false,err end
            return result
        end
    })
end
function M.request(app,target,action,namespace,key,value,callback)
    if type(callback)~="function" then return false,"callback required" end
    if not valid(target,128) or not actions[action] then
        return false,"invalid storage target or action"
    end
    if action~="ping" and action~="namespaces" and not valid(namespace,64) then
        return false,"invalid namespace"
    end
    if (action=="get" or action=="set" or action=="delete")
        and not valid(key,128) then return false,"invalid key" end
    local args={action=action}
    if namespace then args.namespace=namespace end
    if key then args.key=key end
    if action=="set" then args.value=value end
    return app:remoteCommand(target,"storage_agent","storage_request",args,
        function(ok,err,_,ack)
            local result
            if ok and ack and type(ack.value)=="string" then
                local decoded,valueOrErr=pcall(textutils.unserializeJSON,ack.value)
                if decoded then result=valueOrErr else ok=false;err="invalid signed storage result" end
            end
            callback(ok,result,err,ack)
        end)
end
return M
