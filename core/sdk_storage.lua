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
            -- Authenticate the peer first (sdk_commands); deny absent or unconfigured
            -- namespace grants even if the control itself was authorized.
            local origin=app._sdkRemoteOrigin
            local grants=options.namespaces
            local peer=type(origin)=="string" and type(grants)=="table" and grants[origin]
            if request.action=="ping" or request.action=="namespaces" then
                if type(peer)~="table" or peer[request.action]~=true then
                    return false,"storage service access denied"
                end
            else
                local namespaceRules=type(peer)=="table" and peer[request.namespace]
                if type(namespaceRules)~="table" or namespaceRules[request.action]~=true then
                    return false,"storage namespace access denied"
                end
            end
            if not backend then
                local loaded,module=pcall(require,"lib.storage_backend")
                if not loaded then return false,"storage backend unavailable" end
                local created,instance=pcall(module.new,options.backendConfig or {})
                if not created or type(instance)~="table" then
                    return false,"storage backend initialization failed"
                end
                backend=instance
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
            if result==nil then return false,"storage operation returned no result" end
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
    if action=="set" then
        if value==nil then return false,"storage value required" end
        args.value=value
    end
    return app:remoteCommand(target,"storage_agent","storage_request",args,
        function(ok,err,_,ack)
            local result
            if ok and ack and type(ack.value)=="string" then
                local decoded,valueOrErr=pcall(textutils.unserializeJSON,ack.value)
                if decoded then result=valueOrErr else ok=false;err="invalid signed storage result" end
            end
            if ok and (not ack or type(ack.value)~="string") then
                ok=false;err="missing signed storage result"
            end
            callback(ok,result,err,ack)
        end)
end
return M
