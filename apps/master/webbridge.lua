local config = require("lib.config")
local protocol = require("lib.protocol")
local machineInfo = require("lib.machine")
local runtime = require("lib.runtime")
local systemSnapshot = require("lib.system_snapshot")
local adminControl = require("lib.admin_control")
local webcap = require("lib.webcap")

if not fs.exists("/etc/webbridge.lua") then
    runtime.set("app:webbridge", "inactive", { detail = "/etc/webbridge.lua missing" })
    print("Web bridge disabled: /etc/webbridge.lua missing")
    return
end

local web = dofile("/etc/webbridge.lua")
if type(web) ~= "table" then error("/etc/webbridge.lua must return a table") end
if not web.url or web.url == "" then error("Missing web.url in /etc/webbridge.lua") end
if not web.machineToken or web.machineToken == "" then error("Missing web.machineToken in /etc/webbridge.lua") end

local modem = protocol.findWirelessModem()
if not modem then error("Wireless modem introuvable") end

modem.open(config.channels.telemetry)
modem.open(config.channels.ack)
modem.open(config.channels.events)
modem.open(config.channels.nodeStatus)
modem.open(config.channels.nodeAck)
if config.channels.moduleData then modem.open(config.channels.moduleData) end
if config.channels.moduleEvents then modem.open(config.channels.moduleEvents) end
if config.channels.moduleAck then modem.open(config.channels.moduleAck) end

local function connect()
    while true do
        local ws, err = http.websocket(web.url, {
            Authorization = "Bearer " .. web.machineToken,
        })

        if ws then
            runtime.set("app:webbridge", "active", { detail = tostring(web.url) })
            runtime.log("app:webbridge", "info", "WebSocket connected: " .. tostring(web.url))
            print("WebSocket connected")
            webcap.publish("webbridge", {
                connected = true,
                url = tostring(web.url),
                retrySeconds = web.retrySeconds or 3,
            })
            return ws
        end

        runtime.set("app:webbridge", "degraded", { detail = tostring(err) })
        webcap.publish("webbridge", {
            connected = false,
            url = tostring(web.url),
            error = tostring(err),
        })
        runtime.log("app:webbridge", "warning", "WebSocket error: " .. tostring(err))
        print("WebSocket error: " .. tostring(err))
        sleep(web.retrySeconds or 3)
    end
end

local ws = connect()
local localMachine = machineInfo.get("master")
local masterKey = localMachine.key

local seenForward = {}
local function forwardOnce(key)
    local now = protocol.now()
    for k, ts in pairs(seenForward) do
        if now - ts > 3000 then seenForward[k] = nil end
    end
    if seenForward[key] then return false end
    seenForward[key] = now
    return true
end

local function jsonTree(value, stack)
    local kind = type(value)
    if kind == "nil" or kind == "boolean" or kind == "number" or kind == "string" then
        return value
    end
    if kind ~= "table" then
        return tostring(value)
    end

    stack = stack or {}
    if stack[value] then return "<cycle>" end
    stack[value] = true

    local out = {}
    for k, v in pairs(value) do
        local keyType = type(k)
        if keyType == "number" or keyType == "string" then
            out[k] = jsonTree(v, stack)
        end
    end

    stack[value] = nil
    return out
end

local function wsSend(obj)
    -- CC:Tweaked rejects tables which reuse the same table instance in more
    -- than one place. Network snapshots intentionally share structures in
    -- memory, so detach them into a pure JSON tree before serialization.
    local raw = textutils.serializeJSON(jsonTree(obj))
    local ok = pcall(function() ws.send(raw) end)

    if not ok then
        pcall(function() ws.close() end)
        ws = connect()
        ws.send(raw)
    end
end

local function websocketLoop()
    while true do
        local raw = ws.receive()

        if raw == nil then
            ws = connect()
        else
            local msg = textutils.unserializeJSON(raw)

            if type(msg) == "table" and msg.type == "command" then
                local command = protocol.makeModuleCommand(
                    msg.module or "steamplant",
                    msg.command,
                    "web",
                    msg.id,
                    msg.rpm and { rpm = msg.rpm } or (msg.args or {}),
                    msg.targetMachine
                )
                command.network = msg.network or localMachine.network
                modem.transmit(config.channels.control, config.channels.control, command)
            elseif type(msg) == "table" and msg.type == "node_admin" then
                modem.transmit(config.channels.nodeControl, config.channels.nodeControl, {
                    type = "node_admin",
                    id = msg.id,
                    network = msg.network or localMachine.network,
                    targets = msg.targets,
                    request = msg.request,
                    origin = "web",
                    timestamp = protocol.now(),
                })

                local localTarget = false
                if (msg.network or localMachine.network) == localMachine.network
                    and type(msg.targets) == "table"
                then
                    for _, key in ipairs(msg.targets) do
                        if key == masterKey then localTarget = true break end
                    end
                end

                if localTarget then
                    local ok, result = adminControl.handle(msg.request or {})
                    wsSend({
                        type = "node_admin_ack",
                        id = msg.id,
                        key = masterKey,
                        role = localMachine.role,
                        computerId = localMachine.computerId,
                        network = localMachine.network,
                        ok = ok == true,
                        result = ok and result or nil,
                        error = ok and nil or tostring(result),
                        request = msg.request,
                        system = systemSnapshot.build(true),
                        timestamp = protocol.now(),
                    })
                end

            elseif type(msg) == "table" and msg.type == "node_reboot" then
                modem.transmit(config.channels.nodeControl, config.channels.nodeControl, {
                    type = "node_reboot",
                    id = msg.id,
                    network = msg.network or localMachine.network,
                    targets = msg.targets,
                    origin = "web",
                    timestamp = protocol.now(),
                })

                local localTarget = false
                if (msg.network or localMachine.network) == localMachine.network
                    and type(msg.targets) == "table"
                then
                    for _, key in ipairs(msg.targets) do
                        if key == masterKey then
                            localTarget = true
                            break
                        end
                    end
                end

                if localTarget then
                    wsSend({
                        type = "node_reboot_ack",
                        id = msg.id,
                        key = masterKey,
                        role = localMachine.role,
                        computerId = localMachine.computerId,
                        network = localMachine.network,
                        ok = true,
                        timestamp = protocol.now(),
                    })
                    sleep(0.15)
                    os.reboot()
                end
            end
        end
    end
end

local function modemLoop()
    while true do
        local _, _, channel, _, message = os.pullEvent("modem_message")

        if (channel == config.channels.telemetry or channel == config.channels.moduleData)
            and type(message) == "table"
            and message.type == "module_telemetry"
        then
            local dedupeKey = table.concat({
                "telemetry",
                tostring(message.network or localMachine.network),
                tostring(message.machine or ""),
                tostring(message.module or message.source or ""),
                tostring(message.timestamp or ""),
            }, "|")
            if forwardOnce(dedupeKey) then wsSend({
                type = "telemetry",
                network = message.network or localMachine.network,
                module = message.module,
                machine = message.machine,
                data = message,
                timestamp = protocol.now(),
            }) end

        elseif (channel == config.channels.events or channel == config.channels.moduleEvents)
            and type(message) == "table"
            and (message.type == "module_event" or message.type == "plant_event")
        then
            local dedupeKey = table.concat({
                "event",
                tostring(message.network or localMachine.network),
                tostring(message.machine or ""),
                tostring(message.module or ""),
                tostring(message.timestamp or ""),
                tostring(message.code or ""),
            }, "|")
            if forwardOnce(dedupeKey) then wsSend({
                type = "event",
                network = message.network or localMachine.network,
                module = message.module or "steamplant",
                machine = message.machine,
                level = message.level,
                code = message.code,
                message = message.message,
                timestamp = message.timestamp or protocol.now(),
            }) end

        elseif (channel == config.channels.ack or channel == config.channels.moduleAck)
            and type(message) == "table"
            and (message.type == "module_ack" or message.type == "command_ack")
            and message.id
            and tostring(message.id):match("^web%-")
        then
            wsSend({
                type = "command_ack",
                module = message.module or "steamplant",
                id = message.id,
                command = message.command,
                ok = message.ok,
                error = message.error,
                timestamp = protocol.now(),
            })

        elseif channel == config.channels.nodeStatus
            and type(message) == "table"
            and message.type == "node_status"
        then
            wsSend({
                type = "node_status",
                key = message.key,
                role = message.role,
                preset = message.preset or message.role,
                computerId = message.computerId,
                hostname = message.hostname or message.name,
                name = message.name,
                label = message.label,
                apps = message.apps or {},
                modules = message.modules,
                capabilities = message.capabilities or {},
                tags = message.tags,
                network = message.network or localMachine.network,
                networkLabel = message.networkLabel or localMachine.networkLabel,
                topology = message.topology or { links = {} },
                runtime = message.runtime or {},
                system = message.system,
                physicalIdentity = message.physicalIdentity or ("cc:" .. tostring(message.computerId)),
                timestamp = message.timestamp or protocol.now(),
            })

        elseif channel == config.channels.nodeAck
            and type(message) == "table"
            and message.type == "node_admin_ack"
        then
            wsSend({
                type = "node_admin_ack",
                id = message.id,
                key = message.key,
                role = message.role,
                computerId = message.computerId,
                network = message.network or localMachine.network,
                ok = message.ok,
                result = message.result,
                error = message.error,
                request = message.request,
                system = message.system,
                timestamp = message.timestamp or protocol.now(),
            })

        elseif channel == config.channels.nodeAck
            and type(message) == "table"
            and message.type == "node_reboot_ack"
        then
            wsSend({
                type = "node_reboot_ack",
                id = message.id,
                key = message.key,
                role = message.role,
                computerId = message.computerId,
                network = message.network or localMachine.network,
                ok = message.ok,
                timestamp = message.timestamp or protocol.now(),
            })
        end
    end
end

local function heartbeatLoop()
    while true do
        runtime.set("app:webbridge", "active", { detail = tostring(web.url) })
        wsSend({
            type = "node_status",
            key = masterKey,
            role = localMachine.role,
            preset = localMachine.preset,
            capabilities = localMachine.capabilities or {},
            computerId = localMachine.computerId,
            hostname = localMachine.hostname or localMachine.name,
            name = localMachine.name,
            label = localMachine.label,
            apps = localMachine.apps or {},
            modules = localMachine.modules,
            tags = localMachine.tags,
            network = localMachine.network,
            networkLabel = localMachine.networkLabel,
            topology = localMachine.topology,
            runtime = runtime.snapshot().entries or {},
            system = systemSnapshot.build(),
            physicalIdentity = localMachine.physicalIdentity,
            timestamp = protocol.now(),
        })
        sleep(2)
    end
end

parallel.waitForAny(websocketLoop, modemLoop, heartbeatLoop)
