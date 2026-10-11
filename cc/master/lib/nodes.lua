local config = require("lib.config")
local protocol = require("lib.protocol")
local machineInfo = require("lib.machine")

local M = {}

local ANNOUNCE_MS = 2000
local STALE_MS = 7000

local function contains(list, value)
    if type(list) ~= "table" then return false end
    for _, item in ipairs(list) do
        if item == value then return true end
    end
    return false
end

function M.new(modem, role)
    local localMachine = machineInfo.get(role)

    local self = {
        modem = modem,
        role = localMachine.role,
        id = localMachine.computerId,
        key = localMachine.key,
        machine = localMachine,
        nodes = {},
        lastAnnounce = 0,
    }

    modem.open(config.channels.nodeControl)
    modem.open(config.channels.nodeStatus)
    modem.open(config.channels.nodeAck)

    function self:announce(force)
        local now = protocol.now()
        if not force and (now - self.lastAnnounce) < ANNOUNCE_MS then return end
        self.lastAnnounce = now

        local msg = {
            type = "node_status",
            key = self.key,
            role = self.role,
            computerId = self.id,
            name = self.machine.name,
            label = self.machine.label,
            modules = self.machine.modules,
            tags = self.machine.tags,
            physicalIdentity = self.machine.physicalIdentity,
            timestamp = now,
        }

        local previous = self.nodes[self.key]
        local conflictActive = previous
            and previous.conflict
            and previous.conflictSeen
            and (now - previous.conflictSeen) < STALE_MS

        self.nodes[self.key] = {
            key = msg.key,
            role = msg.role,
            computerId = msg.computerId,
            name = msg.name,
            label = msg.label,
            modules = msg.modules,
            tags = msg.tags,
            physicalIdentity = msg.physicalIdentity or ("cc:" .. tostring(msg.computerId)),
            lastSeen = now,
            localNode = true,
            conflict = conflictActive and true or false,
            conflictSeen = conflictActive and previous.conflictSeen or nil,
            conflictPhysicalIdentity = conflictActive and previous.conflictPhysicalIdentity or nil,
        }

        protocol.send(modem, config.channels.nodeStatus, msg)
    end

    function self:prune()
        local now = protocol.now()
        for key, node in pairs(self.nodes) do
            if not node.localNode and (now - (node.lastSeen or 0)) > STALE_MS then
                self.nodes[key] = nil
            elseif node.conflict and node.conflictSeen
                and (now - node.conflictSeen) > STALE_MS
            then
                node.conflict = false
                node.conflictSeen = nil
                node.conflictPhysicalIdentity = nil
            end
        end
    end

    function self:tick()
        self:announce(false)
        self:prune()
    end

    function self:list()
        self:prune()
        local out = {}
        for _, node in pairs(self.nodes) do
            table.insert(out, node)
        end
        table.sort(out, function(a, b)
            if a.role == b.role then
                return (a.computerId or 0) < (b.computerId or 0)
            end
            return tostring(a.role) < tostring(b.role)
        end)
        return out
    end

    function self:sendReboot(targets, origin, id)
        if type(targets) ~= "table" or #targets == 0 then
            return false, "No reboot target"
        end

        protocol.send(modem, config.channels.nodeControl, {
            type = "node_reboot",
            id = id,
            targets = targets,
            origin = origin or self.role,
            timestamp = protocol.now(),
        })
        return true, nil, contains(targets, self.key)
    end

    function self:handle(channel, msg)
        if type(msg) ~= "table" then return nil end

        if channel == config.channels.nodeStatus and msg.type == "node_status" and msg.key then
            local existing = self.nodes[msg.key]
            local incomingPhysical = msg.physicalIdentity or ("cc:" .. tostring(msg.computerId))
            local conflict = existing
                and existing.physicalIdentity
                and incomingPhysical
                and existing.physicalIdentity ~= incomingPhysical

            if msg.key == self.key and incomingPhysical ~= self.machine.physicalIdentity then
                local localNode = existing or {
                    key = self.key,
                    role = self.role,
                    computerId = self.id,
                    name = self.machine.name,
                    label = self.machine.label,
                    modules = self.machine.modules,
                    tags = self.machine.tags,
                    physicalIdentity = self.machine.physicalIdentity,
                    localNode = true,
                }
                localNode.lastSeen = protocol.now()
                localNode.conflict = true
                localNode.conflictSeen = protocol.now()
                localNode.conflictPhysicalIdentity = incomingPhysical
                self.nodes[msg.key] = localNode
            else
                self.nodes[msg.key] = {
                    key = msg.key,
                    role = msg.role or "unknown",
                    computerId = msg.computerId,
                    name = msg.name or msg.key,
                    label = msg.label or msg.key,
                    modules = msg.modules or {},
                    tags = msg.tags or {},
                    physicalIdentity = incomingPhysical,
                    lastSeen = protocol.now(),
                    localNode = msg.key == self.key,
                    conflict = conflict and true or false,
                    conflictSeen = conflict and protocol.now() or nil,
                    conflictPhysicalIdentity = conflict and existing.physicalIdentity or nil,
                }
            end
            return conflict and "identity_conflict" or "status", msg
        end

        if channel == config.channels.nodeAck and msg.type == "node_reboot_ack" then
            return "ack", msg
        end

        if channel == config.channels.nodeControl
            and msg.type == "node_reboot"
            and contains(msg.targets, self.key)
        then
            protocol.send(modem, config.channels.nodeAck, {
                type = "node_reboot_ack",
                id = msg.id,
                key = self.key,
                role = self.role,
                computerId = self.id,
                ok = true,
                timestamp = protocol.now(),
            })
            return "reboot", msg
        end

        return nil
    end

    self:announce(true)
    return self
end

return M
