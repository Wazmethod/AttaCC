-- SDK node discovery service, independent from the legacy Master node manager.
-- Passive listener: no reboot or administration controls are exposed.
local M={}
function M.new(machine,options)
    options=options or {}
    local self={nodes={}}
    local staleMs=tonumber(options.staleMs) or 12000
    local function now() return os.epoch("utc") end
    function self:accept(message,authenticatedOrigin)
        if type(message)~="table" or type(authenticatedOrigin)~="string"
            or authenticatedOrigin~=message.key then
            return false,"node origin mismatch"
        end
        if type(message)~="table" or message.type~="attacc.sdk.node.v1"
            or type(message.key)~="string" or message.key==""
            or type(message.network)~="string"
            or message.network~=machine.network then return false end
        local old=self.nodes[message.key]
        local identity=message.physicalIdentity or
            (message.computerId and ("cc:"..tostring(message.computerId)))
        local conflict=old and old.physicalIdentity and identity
            and old.physicalIdentity~=identity
        if conflict then
            old.conflict=true
            old.conflictSeen=now()
            return false,"identity conflict"
        end
        self.nodes[message.key]={
            key=message.key,network=message.network,
            hostname=message.hostname or message.name or message.key,
            role=message.role,preset=message.preset,
            computerId=message.computerId,
            physicalIdentity=identity,
            apps=type(message.apps)=="table" and message.apps or {},
            modules=type(message.modules)=="table" and message.modules or {},
            capabilities=type(message.capabilities)=="table" and message.capabilities or {},
            tags=type(message.tags)=="table" and message.tags or {},
            runtime=type(message.runtime)=="table" and message.runtime or {},
            system=type(message.system)=="table" and message.system or nil,
            uptimeSeconds=tonumber(message.uptimeSeconds),
            seen=now(),conflict=old and old.conflict or false
        }
        return true
    end
    function self:list()
        local list={}
        for _,node in pairs(self.nodes) do
            node.online=now()-node.seen<=staleMs
            list[#list+1]=node
        end
        table.sort(list,function(a,b) return a.key<b.key end)
        return list
    end
    function self:get(key) return self.nodes[key] end
    return self
end
return M
