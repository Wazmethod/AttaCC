-- SDK command transport, independent of application and modem event loops.
-- A network name is NOT authentication. Callers must supply an authorizer.
local M={}
local function now() return os.epoch("utc") end
function M.new(app, options)
    assert(type(app)=="table" and type(app.invoke)=="function", "SDK app required")
    options=options or {}
    local self={seen={}}
    function self:handle(message)
        if type(message)~="table" or message.type~="attacc.sdk.command.v1" then
            return nil,"not an SDK command"
        end
        local function ack(ok,err)
            return {type="attacc.sdk.ack.v1",id=message.id,app=app.id,
                ok=ok==true,error=err,timestamp=now()}
        end
        if message.app~=app.id then return ack(false,"wrong app") end
        if type(message.id)~="string" or #message.id<1 or #message.id>128
            or type(message.control)~="string" or #message.control>64 then
            return ack(false,"invalid request")
        end
        if options.network and message.network~=options.network then
            return ack(false,"wrong network")
        end
        if options.machine and message.target~=options.machine then
            return ack(false,"wrong target")
        end
        if type(message.timestamp)~="number" or
            math.abs(now()-message.timestamp)> (options.maxAgeMs or 10000) then
            return ack(false,"expired command")
        end
        for id, entry in pairs(self.seen) do
            if now()-entry.at > (options.dedupeMs or 30000) then self.seen[id]=nil end
        end
        local dedupe=(message.origin or "")..":"..message.id
        if self.seen[dedupe] then return self.seen[dedupe].ack end
        if type(options.authorize)~="function" then
            return ack(false,"remote authorization not configured")
        end
        local approved, allowed=pcall(options.authorize,message)
        if not approved or allowed~=true then
            return ack(false,"unauthorized")
        end
        local control=app.controls and app.controls[message.control]
        if not control or control.remote~=true then
            return ack(false,"control not exposed remotely")
        end
        if type(message.args)~="table" then return ack(false,"invalid arguments") end
        local ok,result=app:invoke(message.control,table.unpack(message.args))
        local response=ack(ok,not ok and tostring(result) or nil)
        self.seen[dedupe]={at=now(),ack=response}
        return response
    end
    return self
end
return M
