-- Event-driven WebSocket transport for AttaCC SDK services.
-- Connection lifecycle is owned by the SDK host; no parallel event loop.
local M={}
function M.new(options)
    options=options or {}
    local self={state="inactive",connection=nil,error=nil}
    local url=options.url
    local retry=math.max(1,tonumber(options.retrySeconds) or 3)
    local retryTimer=nil
    local function notify()
        if type(options.onState)=="function" then
            pcall(options.onState,self.state,self.error)
        end
    end
    local function reconnect()
        if not retryTimer then retryTimer=os.startTimer(retry) end
    end
    function self:connect()
        if type(url)~="string" or url=="" then
            self.state="inactive";self.error="WebSocket URL missing";notify()
            return false,self.error
        end
        if type(options.token)~="string" or options.token=="" then
            self.state="inactive";self.error="WebSocket token missing";notify()
            return false,self.error
        end
        if not http or type(http.websocketAsync)~="function" then
            self.state="degraded";self.error="websocketAsync unavailable"
            notify();return false,self.error
        end
        self.state="connecting";self.error=nil;notify()
        local ok,started,err=pcall(http.websocketAsync,url,{
            Authorization="Bearer "..options.token
        })
        if not ok or started==false then
            self.state="degraded";self.error=tostring(err or started);notify();reconnect()
            return false,self.error
        end
        return true
    end
    function self:send(message)
        if self.state~="active" or not self.connection then
            return false,"WebSocket disconnected"
        end
        if type(message)~="table" then return false,"message table required" end
        local ok,raw=pcall(textutils.serializeJSON,message)
        if not ok or type(raw)~="string" then return false,"invalid payload" end
        local sent,err=pcall(self.connection.send,raw)
        if not sent then return false,tostring(err) end
        return true
    end
    function self:handle(event,a,b,c)
        if event=="timer" and retryTimer and a==retryTimer then
            retryTimer=nil;self:connect();return true
        end
        if a~=url then return false end
        if event=="websocket_success" then
            self.connection=b;self.state="active";self.error=nil;notify()
            return true
        elseif event=="websocket_failure" or event=="websocket_closed" then
            self.connection=nil;self.state="degraded"
            self.error=event=="websocket_failure" and tostring(b) or "closed"
            notify();reconnect();return true
        elseif event=="websocket_message" then
            local ok,message=pcall(textutils.unserializeJSON,b)
            if ok and type(message)=="table" and type(options.onMessage)=="function" then
                pcall(options.onMessage,message,c)
            end
            return true
        end
        return false
    end
    function self:close()
        if self.connection then pcall(self.connection.close) end
        self.connection=nil;self.state="inactive"
    end
    return self
end
return M
