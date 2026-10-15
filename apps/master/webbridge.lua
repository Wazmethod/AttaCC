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
modem.open(config.channels.sdkSnapshot or 4259)
modem.open(config.channels.sdkAck or 4258)
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
local seenNetworks = { [localMachine.network] = true }
local networkLabels = type(web.networkLabels) == "table" and web.networkLabels or {}

local function saveSeenNetworks()
    local list = {}
    for id in pairs(seenNetworks) do table.insert(list, id) end
    table.sort(list)
    if not fs.exists("/run/attacc") then fs.makeDir("/run/attacc") end
    local h = fs.open("/run/attacc/webbridge-networks.json", "w")
    if h then h.write(textutils.serializeJSON(list)); h.close() end
end

local function rememberNetwork(id)
    id = tostring(id or "default")
    if not seenNetworks[id] then
        seenNetworks[id] = true
        saveSeenNetworks()
    end
    return id
end

local function reloadLabels()
    local ok, cfg = pcall(dofile, "/etc/webbridge.lua")
    if ok and type(cfg) == "table" and type(cfg.networkLabels) == "table" then
        networkLabels = cfg.networkLabels
    end
end

local function networkLabel(id)
    id = rememberNetwork(id)
    return networkLabels[id] or id
end

saveSeenNetworks()

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
                local sdkCommands=require("lib.sdk_commands")
                local args=msg.rpm and {rpm=msg.rpm} or (msg.args or {})
                local command,sdkErr
                if msg.targetMachine then
                    command,sdkErr=sdkCommands.clientRequest(
                        msg.module or "steamplant",msg.command,"web",msg.targetMachine,
                        msg.network or localMachine.network,msg.id,args)
                else
                    sdkErr="not_enabled"
                end
                if command then
                    modem.transmit(config.channels.sdkControl or 4257,
                        config.channels.sdkControl or 4257,command)
                elseif sdkErr=="not_enabled" then
                    local legacy = protocol.makeModuleCommand(
                    msg.module or "steamplant",
                    msg.command,
                    "web",
                    msg.id,
                    args,
                    msg.targetMachine
                )
                legacy.network = msg.network or localMachine.network
                modem.transmit(config.channels.control, config.channels.control, legacy)
                else
                    wsSend({type="command_ack",id=msg.id,command=msg.command,
                        module=msg.module,ok=false,error="SDK signing failed: "..tostring(sdkErr)})
                end
            elseif type(msg) == "table" and msg.type == "node_admin" then
                runtime.log("app:webbridge", "info",
                    "forward admin " .. tostring(msg.request and msg.request.action or "?")
                    .. " -> " .. table.concat(type(msg.targets)=="table" and msg.targets or {}, ","))
                modem.transmit(config.channels.nodeControl, config.channels.nodeControl, {
                    type = "node_admin",
                    id = msg.id,
                    network = msg.network or localMachine.network,
                    targets = msg.targets,
                    request = msg.request,
                    global = msg.global == true,
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
                runtime.log("app:webbridge", "info",
                    "forward reboot -> " .. table.concat(type(msg.targets)=="table" and msg.targets or {}, ","))
                modem.transmit(config.channels.nodeControl, config.channels.nodeControl, {
                    type = "node_reboot",
                    id = msg.id,
                    network = msg.network or localMachine.network,
                    targets = msg.targets,
                    global = msg.global == true,
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

        if channel == (config.channels.sdkSnapshot or 4259) and type(message)=="table"
            and message.type=="attacc.sdk.snapshot.v1" then
            local compat=require("lib.sdk_snapshot").compat(message)
            if compat then
                local dedupeKey=table.concat({"sdk",tostring(message.network),
                    tostring(message.machine),tostring(message.module),tostring(message.timestamp)},"|")
                if forwardOnce(dedupeKey) then
                    wsSend({type="sdk_snapshot",network=rememberNetwork(message.network),
                        module=message.module,machine=message.machine,
                        descriptor=message.descriptor,data=compat,timestamp=message.timestamp})
                end
            end
        elseif (channel == config.channels.telemetry or channel == config.channels.moduleData)
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
                network = rememberNetwork(message.network or localMachine.network),
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
                network = rememberNetwork(message.network or localMachine.network),
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
                network = rememberNetwork(message.network or localMachine.network),
                networkLabel = networkLabel(message.network or localMachine.network),
                
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
                network = rememberNetwork(message.network or localMachine.network),
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
                network = rememberNetwork(message.network or localMachine.network),
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
            networkLabel = networkLabel(localMachine.network),
            
            runtime = runtime.snapshot().entries or {},
            system = systemSnapshot.build(),
            physicalIdentity = localMachine.physicalIdentity,
            timestamp = protocol.now(),
        })
        sleep(2)
    end
end

local function uiLoop()
    local function draw()
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.clear()
        term.setCursorPos(2,1)
        term.setTextColor(colors.cyan)
        write("ATTACC WEBBRIDGE")
        term.setCursorPos(2,3)
        term.setTextColor(colors.lightGray)
        write("URL      ")
        term.setTextColor(colors.white)
        write(tostring(web.url))
        term.setCursorPos(2,4)
        term.setTextColor(colors.lightGray)
        write("Network  ")
        term.setTextColor(colors.white)
        write(tostring(localMachine.network))
        term.setCursorPos(2,6)
        term.setTextColor(colors.yellow)
        write("SEEN NETWORKS")
        local y=7
        local list={}
        for id in pairs(seenNetworks) do table.insert(list,id) end
        table.sort(list)
        for _,id in ipairs(list) do
            term.setCursorPos(2,y)
            term.setTextColor(colors.white)
            write(tostring(id))
            term.setCursorPos(20,y)
            term.setTextColor(colors.gray)
            write(tostring(networkLabel(id)))
            y=y+1
        end
        term.setCursorPos(2,math.max(y+1,12))
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.white)
        write(" NETWORK LABELS ")
        term.setBackgroundColor(colors.black)
        term.setCursorPos(20,math.max(y+1,12))
        term.setBackgroundColor(colors.gray)
        write(" REFRESH ")
        term.setBackgroundColor(colors.black)
    end

    draw()
    while true do
        local event,p1,p2,p3=os.pullEvent()
        if event=="mouse_click" then
            local _,h=term.getSize()
            local y=math.max((function()
                local n=0 for _ in pairs(seenNetworks) do n=n+1 end
                return 7+n+1
            end)(),12)
            if p3==y and p2>=2 and p2<=17 then
                if shell.openTab then
                    local id=shell.openTab("webbridgectl.lua", "configure")
                    if id and multishell and multishell.setTitle then
                        pcall(multishell.setTitle,id,"webbridge-config")
                    end
                    if id and multishell and multishell.setFocus then
                        pcall(multishell.setFocus,id)
                    end
                else
                    shell.run("webbridgectl.lua", "configure")
                end
            elseif p3==y and p2>=20 and p2<=28 then
                reloadLabels()
                draw()
            end
        elseif event=="key" and p1==keys.r then
            reloadLabels()
            draw()
        elseif event=="timer" or event=="modem_message" then
            reloadLabels()
            draw()
        end
    end
end

parallel.waitForAny(websocketLoop, modemLoop, heartbeatLoop, uiLoop)
