-- Master SDK -> existing AttaCC WebSocket control-plane protocol.
-- Uses the SDK host's WebSocket lifecycle; no second modem/event loop.
-- Data/events discovery are bridged; remote admin execution is not granted here.
local M={}

local CONFIG="/etc/webbridge.lua"
local function safeList(value)
    return type(value)=="table" and value or {}
end

function M.new(app)
    local self={enabled=false,error=nil,lastNodePublish=0,connection="disabled"}
    if not fs.exists(CONFIG) then
        return self
    end
    local ok,cfg=pcall(dofile,CONFIG)
    if not ok or type(cfg)~="table" then
        self.error="invalid "..CONFIG
        return self
    end
    local url=cfg.url
    local token=cfg.machineToken
    if type(url)~="string" or not url:match("^wss?://.+/ws/machine$")
        or type(token)~="string" or token=="" then
        self.error="configure URL and machineToken with webbridgectl"
        return self
    end
    self.enabled=true
    self.connection="connecting"
    local machine=require("lib.machine").get(app.id)
    local snapshots=require("lib.sdk_snapshot")
    local runtime=require("lib.runtime")
    local seen={}
    local sentSnapshots=0
    local sentEvents=0
    local announcedCapabilities=false

    local function forward(frame)
        if app:webStatus()~="active" then return false end
        return app:webSend(frame)
    end

    -- The browser backend already consumes legacy *wire message names*, but
    -- the values here are native SDK descriptors, never legacy app state.
    app:onSnapshot(function(frame)
        if frame.network~=machine.network then return end
        local key=table.concat({frame.network,frame.machine,frame.module or frame.descriptor.id},":")
        if seen[key]==frame.timestamp then return end
        seen[key]=frame.timestamp
        local telemetry,err=snapshots.compat(frame)
        if not telemetry then
            app:log("warning","WebBridge snapshot: "..tostring(err))
            return
        end
        local sent=forward({
            type="telemetry",network=frame.network,machine=frame.machine,
            module=frame.module or frame.descriptor.id,
            timestamp=frame.timestamp,data=telemetry
        })
        if sent then sentSnapshots=sentSnapshots+1 end
    end)

    app:onNetwork("app.event",function(payload,frame)
        if type(payload)~="table" or frame.network~=machine.network then return end
        local sent=forward({
            type="event",network=frame.network,
            machine=frame.origin,module=frame.module,
            timestamp=frame.timestamp or os.epoch("utc"),
            level=payload.level or "info",
            code=payload.code or "APP_EVENT",
            message=tostring(payload.message or payload.code or "SDK event")
        })
        if sent then sentEvents=sentEvents+1 end
    end)

    local function nodeMessage(node,timestamp)
        return {
            type="node_status",key=node.key,
            role=node.role or "unknown",preset=node.preset,
            computerId=node.computerId,
            hostname=node.hostname or node.name or node.key,
            name=node.name or node.hostname or node.key,
            label=node.label or node.hostname or node.key,
            apps=safeList(node.apps),modules=safeList(node.modules),
            capabilities=safeList(node.capabilities),tags=safeList(node.tags),
            network=node.network or machine.network,
            runtime=safeList(node.runtime),system=node.system,
            physicalIdentity=node.physicalIdentity,
            timestamp=timestamp
        }
    end

    function self:tick()
        if not self.enabled or app:webStatus()~="active" then return end
        local now=os.epoch("utc")
        if not announcedCapabilities then
            announcedCapabilities=forward({
                type="bridge_capabilities",protocol="attacc.sdk.v1",
                commands=false,network=machine.network
            })
        end
        if now-self.lastNodePublish<2000 then return end
        self.lastNodePublish=now
        forward(nodeMessage({
            key=machine.key,role=machine.role,preset=machine.preset,
            computerId=machine.computerId,hostname=machine.hostname,
            name=machine.name,label=machine.label,
            apps=machine.apps,modules=machine.modules,
            capabilities=machine.capabilities,tags=machine.tags,
            network=machine.network,physicalIdentity=machine.physicalIdentity,
            runtime=runtime.snapshot().entries or {}
        },now))
        for _,node in ipairs(app:nodes()) do
            if node.online and node.key~=machine.key then
                forward(nodeMessage(node,now))
            end
        end
    end

    function self:status()
        if not self.enabled then return self.error or "disabled" end
        return app:webStatus()
    end
    function self:stats() return sentSnapshots,sentEvents end

    self.websocket={
        url=url,token=token,retrySeconds=cfg.retrySeconds or 3,
        -- Preserve previously configured ws:// LAN bridges. Prefer wss://
        -- when the endpoint is reached through a public HTTPS proxy.
        allowInsecure=url:sub(1,5)=="ws://",
        onState=function(state,err)
            self.connection=state
            self.error=err
            if state~="active" then
                announcedCapabilities=false
                self.lastNodePublish=0
            end
            runtime.set("app:webbridge",state=="active" and "active" or "degraded",
                {detail=state=="active" and "SDK Master bridge connected"
                    or tostring(err or state)})
        end
    }
    return self
end

return M
