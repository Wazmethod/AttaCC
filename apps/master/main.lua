local config = require("lib.config")
local protocol = require("lib.protocol")
local displayCore = require("lib.display")
local display = require("lib.master_display")
local nodes = require("lib.nodes")
local runtime = require("lib.runtime")
local bus = require("lib.bus")
local network = require("lib.network")
local okStorageBackend, storageBackend = pcall(require, "lib.storage_backend")
local webcap = require("lib.webcap")

local modem = protocol.findWirelessModem()
if not modem then error("Wireless modem introuvable") end

local nodeBus = nodes.new(modem, "master")
local net = network.new(config, nodeBus.machine)
local localStore = okStorageBackend and storageBackend.new(config) or nil

local monitor, monitorName = nil, nil
local displayWidth, displayHeight = nil, nil
local displayState = "unknown"
local displayFaultReported = false
local speaker = peripheral.find("speaker")

local page = "home"
local machineTab = "data"
local machinePage = 1
local selectedAppKey = nil
local controlApps = {}
local events = {}
local EVENT_LIMIT = 100
local EVENT_STORAGE_NAMESPACE = "attacc.events"
local EVENT_STORAGE_KEY = "master:" .. tostring(nodeBus.machine.key)
local eventPersistencePending = false
local storageClient = require("lib.storage_client")
local storageProfile = require("lib.profile_store")
local function restoreEvents()
    local cfg = storageProfile.storageConfig()
    if not cfg.enabled or not cfg.targetMachine then return end
    local old, err = storageClient.get(EVENT_STORAGE_NAMESPACE,EVENT_STORAGE_KEY,2)
    if err then
        runtime.log("master","warning","Event history unavailable: "..tostring(err))
        return
    end
    if type(old) ~= "table" then return end
    for index = #old,1,-1 do
        if type(old[index]) == "table" then table.insert(events,1,old[index]) end
    end
    while #events > EVENT_LIMIT do table.remove(events) end
end
local function saveEvents()
    if not eventPersistencePending then return end
    local cfg = storageProfile.storageConfig()
    if not cfg.enabled or not cfg.targetMachine then return end
    local compact = {}
    for _,entry in ipairs(events) do
        compact[#compact+1] = {
            hostname = tostring(entry.hostname or ""):sub(1,40),
            machine = tostring(entry.machine or entry.source or ""):sub(1,48),
            code = tostring(entry.code or ""):sub(1,32),
            level = tostring(entry.level or "info"):sub(1,9),
            message = tostring(entry.message or ""):sub(1,100),
            timestamp = entry.timestamp,
            type = tostring(entry.type or "module_event"):sub(1,20),
        }
    end
    local _,err = storageClient.set(EVENT_STORAGE_NAMESPACE,EVENT_STORAGE_KEY,compact,2)
    if err then
        runtime.log("master","warning","Event persistence failed: "..tostring(err))
        return
    end
    eventPersistencePending = false
end
restoreEvents()
local pending = nil
local commandSeq = 1

local localPage = "home"
local localHitboxes = {}
local notices = {}

local function notice(level, message)
    table.insert(notices, 1, {
        level = level or "info",
        message = tostring(message),
        at = textutils.formatTime(os.time(), true),
    })
    while #notices > 5 do table.remove(notices) end
    runtime.log("master", level == "warn" and "warning" or level, tostring(message))
end

local function appKey(message)
    if type(message) ~= "table" or type(message.ui) ~= "table" then return nil end
    local app = message.ui.app
    if type(app) ~= "table" then return nil end
    local machineKey = app.machine or message.machine
    local moduleId = app.module or message.module
    if not machineKey or not moduleId then return nil end
    return tostring(message.network or nodeBus.machine.network)
        .. ":" .. tostring(machineKey)
        .. ":" .. tostring(moduleId)
end

local function graphDescriptors(message)
    local ui = message and message.ui
    if type(ui) ~= "table" then return {} end

    if type(ui.graphs) == "table" and #ui.graphs > 0 then
        return ui.graphs
    end

    local out, seen = {}, {}
    local function add(metric, groupId)
        if type(metric) ~= "table" then return end
        local value = tonumber(metric.value)
        if value == nil then return end
        local id = tostring(metric.id or ((groupId and (groupId .. "_") or "")
            .. tostring(metric.label or #out + 1))):lower():gsub("[^%w_%-]", "_")
        if seen[id] then return end
        seen[id] = true
        table.insert(out, {
            id = id,
            label = metric.label or id,
            value = value,
            unit = metric.unit,
        })
    end

    for _, metric in ipairs(type(ui.metrics) == "table" and ui.metrics or {}) do
        add(metric)
    end
    for _, group in ipairs(type(ui.groups) == "table" and ui.groups or {}) do
        for _, metric in ipairs(type(group.metrics) == "table" and group.metrics or {}) do
            add(metric, group.id)
        end
    end
    return out
end

local function rememberControlApp(message)
    local key = appKey(message)
    if not key then return false end

    local previous = controlApps[key] or {}
    local history = previous.history or {}
    local timestamp = message.timestamp or protocol.now()

    for _, series in ipairs(graphDescriptors(message)) do
        local id = tostring(series.id or series.label or "value")
        local bucket = history[id] or {}
        local last = bucket[#bucket]
        if not last or last.timestamp ~= timestamp then
            table.insert(bucket, {
                timestamp = timestamp,
                value = tonumber(series.value) or 0,
                label = tostring(series.label or id),
                unit = series.unit,
            })
            while #bucket > ((config.master and config.master.historySamples) or 120) do
                table.remove(bucket, 1)
            end
        end
        history[id] = bucket
    end

    controlApps[key] = {
        key = key,
        network = message.network or nodeBus.machine.network,
        machine = message.ui.app.machine or message.machine,
        machineLabel = message.ui.app.machineLabel,
        module = message.ui.app.module or message.module,
        appId = message.ui.app.id or message.module,
        title = message.ui.app.title or message.ui.title or message.module,
        data = message,
        seenAt = protocol.now(),
        history = history,
    }

    if not selectedAppKey then selectedAppKey = key end
    return true
end

local function controlAppList(includeHistory)
    local now = protocol.now()
    local out = {}
    for key, item in pairs(controlApps) do
        table.insert(out, {
            key = key,
            network = item.network,
            machine = item.machine,
            machineLabel = item.machineLabel,
            module = item.module,
            appId = item.appId,
            title = item.title,
            fresh = (now - item.seenAt) < config.timing.sourceStaleMs,
            ageMs = now - item.seenAt,
            data = item.data,
            history = includeHistory and item.history or nil,
        })
    end
    table.sort(out, function(a,b)
        return tostring(a.machineLabel or a.machine or a.key)
            < tostring(b.machineLabel or b.machine or b.key)
    end)
    return out
end

local function selectedApp()
    if selectedAppKey and controlApps[selectedAppKey] then return controlApps[selectedAppKey] end
    local list = controlAppList(false)
    if list[1] then
        selectedAppKey = list[1].key
        return controlApps[selectedAppKey]
    end
    return nil
end

local function selectApp(key)
    if controlApps[key] then
        selectedAppKey = key
        machineTab = "data"
        machinePage = 1
        return true
    end
    return false
end

local function hostnameFor(machineKey)
    for _, node in ipairs(nodeBus:list()) do
        if node.key == machineKey then return node.hostname or node.label or node.key end
    end
    for _, app in pairs(controlApps) do
        if app.machine == machineKey then return app.machineLabel or app.machine end
    end
    return machineKey or "unknown"
end

local knownLifecycleNodes = {}

local function pushEvent(event)
    event = event or {}
    if not event.hostname then event.hostname = hostnameFor(event.machine or event.source) end
    table.insert(events, 1, event)
    while #events > EVENT_LIMIT do table.remove(events) end
    eventPersistencePending = true

    if speaker then
        pcall(function()
            if event.level == "critical" then
                speaker.playNote("bell", 1, 6)
            elseif event.level == "warning" then
                speaker.playNote("bell", 0.8, 10)
            elseif event.level == "success" then
                speaker.playNote("chime", 0.8, 12)
            end
        end)
    end
end

local function refreshDisplay(force)
    local found, foundNameOrErr = displayCore.find("auto")
    local foundName = found and foundNameOrErr or nil

    if not found then
        if monitor then pcall(display.shutdown, monitor) end
        if displayState ~= "inactive" then notice("warn", "Display -> no monitor detected") end
        monitor, monitorName = nil, nil
        displayWidth, displayHeight = nil, nil
        displayState = "inactive"
        runtime.set("module:core.display", "inactive", {
            detail = tostring(foundNameOrErr or "no monitor detected"),
        })
        return false
    end

    local width, height = displayCore.geometry(found)
    local geometryChanged = monitorName == foundName
        and displayWidth ~= nil
        and (displayWidth ~= width or displayHeight ~= height)
    local changedMonitor = monitorName ~= foundName

    if monitor and not changedMonitor and not geometryChanged and not force then return true end

    local oldGeometry = displayWidth and (tostring(displayWidth) .. "x" .. tostring(displayHeight)) or nil
    if monitor and changedMonitor then pcall(display.shutdown, monitor) end

    local ok, status = pcall(display.init, found)
    if not ok then
        if displayState ~= "degraded" then notice("warn", "Display -> init failed: " .. tostring(status)) end
        monitor, monitorName = nil, nil
        displayWidth, displayHeight = nil, nil
        displayState = "degraded"
        runtime.set("module:core.display", "degraded", { detail = tostring(status) })
        return false
    end

    monitor, monitorName = found, foundName
    displayWidth, displayHeight = width, height
    displayFaultReported = false
    displayState = status.degraded and "degraded" or "active"

    runtime.set("module:core.display", displayState, {
        device = monitorName,
        backend = status.backend,
        width = width,
        height = height,
        detail = status.error or "Master display active",
    })

    local geometry = tostring(width) .. "x" .. tostring(height)
    if geometryChanged and oldGeometry then
        notice("info", "Display -> resolution changed " .. oldGeometry .. " -> " .. geometry)
    elseif changedMonitor or force or not oldGeometry then
        notice(status.degraded and "warn" or "info",
            "Display -> " .. tostring(monitorName) .. " active (" .. geometry .. ", "
            .. tostring(status.backend) .. ")")
    end
    return true
end

local function refreshSpeaker()
    speaker = peripheral.find("speaker")
end

local function webState()
    if not fs.exists("/etc/webbridge.lua") then return "disabled", "not configured" end
    local snapshot = runtime.snapshot()
    local item = snapshot.entries and snapshot.entries["app:webbridge"] or nil
    return item and item.status or "starting", item and item.detail or "configured"
end

local function storageState()
    if localStore then
        local stats = localStore:stats()
        stats.status = stats.available and "active" or "degraded"
        return stats
    end
    local cfg = storageProfile.storageConfig()
    if cfg.enabled and cfg.targetMachine and cfg.targetMachine ~= "" then
        return { available = true, backend = "client", status = "active",
            targetMachine = cfg.targetMachine }
    end
    if cfg.enabled then
        return { available = false, backend = "client", status = "degraded",
            error = "Storage client enabled without a target" }
    end
    return { available = false, backend = "none", status = "inactive",
        error = "Storage not configured" }
end

local function broadcastPocket()
    local app = selectedApp()
    protocol.send(modem, config.channels.pocketStatus, {
        type = "module_status",
        module = app and app.module or nil,
        masterTimestamp = protocol.now(),
        sourceTimestamp = app and app.data and app.data.timestamp or nil,
        sourceAgeMs = app and (protocol.now() - app.seenAt) or nil,
        sourceFresh = app and (protocol.now() - app.seenAt) < config.timing.sourceStaleMs or false,
        data = app and app.data or nil,
        apps = controlAppList(false),
        events = events,
    })
end

local function commandId()
    local id = "master-" .. tostring(os.getComputerID()) .. "-"
        .. tostring(protocol.now()) .. "-" .. tostring(commandSeq)
    commandSeq = commandSeq + 1
    return id
end

local function transmitPending()
    if not pending then return end
    protocol.send(modem, pending.sdk and (config.channels.sdkControl or 4257) or config.channels.control, pending.message)
    pending.sentAt = protocol.now()
    pending.retries = pending.retries + 1
end

local function send(control)
    if pending then return false end
    local app = selectedApp()
    if not app then return false end

    local command = type(control) == "table" and control.command or control
    if not command then return false end

    local args = {}
    if type(control) == "table" and type(control.args) == "table" then
        for k,v in pairs(control.args) do args[k] = v end
    end
    if type(control) == "table" and control.rpm ~= nil then args.rpm = control.rpm end

    local id = commandId()
    local sdkCommands=require("lib.sdk_commands")
    local msg, sdkErr=sdkCommands.clientRequest(
        app.module,command,"master",app.machine,nodeBus.machine.network,id,args
    )
    local usingSdk=msg~=nil
    if not usingSdk and sdkErr~="not_enabled" then
        runtime.log("master","error","SDK command rejected: "..tostring(sdkErr))
        return false
    end
    if not usingSdk then
        msg = protocol.makeModuleCommand(app.module,command,"master",id,args,app.machine)
    end
    pending = {
        id = id,
        message = msg,
        sdk = usingSdk,
        command = command,
        module = app.module,
        targetMachine = app.machine,
        sentAt = 0,
        retries = 0,
    }
    transmitPending()
    return true
end

local function monitorState()
    local webStatus, webDetail = webState()
    return {
        page = page,
        machineTab = machineTab,
        machinePage = machinePage,
        selectedAppKey = selectedAppKey,
        apps = controlAppList(true),
        events = events,
        nodes = nodeBus:list(),
        pending = pending,
        now = protocol.now(),
        home = config.master and config.master.home or {},
        storage = storageState(),
        web = { status = webStatus, detail = webDetail },
        display = {
            state = displayState,
            name = monitorName,
            width = displayWidth,
            height = displayHeight,
            backend = monitor and display.getStatus().backend or nil,
        },
    }
end

local function redraw()
    if not monitor then return false, "display inactive" end

    local ok, err = display.draw(monitor, monitorState())
    if ok then
        runtime.set("module:core.display", "active", {
            device = monitorName,
            backend = display.getStatus().backend,
            detail = "Master display renderer active",
        })
    else
        runtime.set("module:core.display", "degraded", {
            device = monitorName,
            backend = display.getStatus().backend,
            detail = tostring(err),
        })
        if not displayFaultReported then
            displayFaultReported = true
            pushEvent({
                type = "module_event",
                level = "warning",
                code = "DISPLAY_FALLBACK",
                message = "Graphics renderer failed; text fallback active: " .. tostring(err),
                timestamp = protocol.now(),
                source = "master",
                machine = nodeBus.machine.key,
            })
        end
    end
    return ok, err
end

local function localButton(x, y, label, key, action)
    term.setCursorPos(x, y)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    write(" " .. label .. " ")
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    table.insert(localHitboxes, {
        x1 = x, x2 = x + #label + 1, y = y, key = key, action = action,
    })
end

local function drawLocalHeader(title)
    localHitboxes = {}
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(2, 1)
    term.setTextColor(colors.cyan)
    write("ATTACC MASTER")
    term.setTextColor(colors.gray)
    write("  /  " .. tostring(title))
    term.setCursorPos(2, 3)
    term.setTextColor(colors.white)
    write(tostring(nodeBus.machine.hostname or nodeBus.machine.key))
    term.setTextColor(colors.gray)
    write("  " .. tostring(nodeBus.machine.network))
    term.setTextColor(colors.white)
end

local function drawLocalHome()
    drawLocalHeader("HOME")
    local nodeList = nodeBus:list()
    local store = storageState()
    local webStatus, webDetail = webState()

    local rows = {
        { "Network", "ACTIVE", #nodeList .. " node(s)", colors.lime },
        { "Machines", tostring(#controlAppList(false)), "controllable app(s)", colors.lime },
        { "Storage", string.upper(store.status or "inactive"),
            store.available and tostring(store.backend or "local") or tostring(store.error or ""), store.available and colors.lime or colors.orange },
        { "Display", string.upper(displayState), monitorName and
            (tostring(monitorName) .. " " .. tostring(displayWidth or "?") .. "x" .. tostring(displayHeight or "?"))
            or "no monitor", displayState == "active" and colors.lime or colors.orange },
        { "Web", string.upper(tostring(webStatus)), tostring(webDetail or ""),
            webStatus == "active" and colors.lime or webStatus == "degraded" and colors.red or colors.orange },
    }

    local y = 5
    for _, row in ipairs(rows) do
        term.setCursorPos(2, y)
        term.setTextColor(colors.lightGray)
        write(string.format("%-9s ", row[1]))
        term.setTextColor(row[4])
        write(string.format("%-9s", row[2]))
        term.setTextColor(colors.gray)
        write(" " .. row[3])
        y = y + 1
    end

    term.setCursorPos(2, 12)
    term.setTextColor(colors.yellow)
    write("TOOLS")
    localButton(2, 14, "Network", keys.n, "nodes")
    localButton(14, 14, "Display", keys.d, "display")
    localButton(2, 16, "Home Config", keys.h, "home_config")
    localButton(18, 16, "Refresh", keys.r, "refresh")

    term.setCursorPos(2, 18)
    term.setTextColor(colors.yellow)
    write("RECENT")
    y = 19
    for _, item in ipairs(notices) do
        term.setCursorPos(2, y)
        term.setTextColor(item.level == "warn" and colors.orange
            or item.level == "error" and colors.red or colors.lightGray)
        write(item.at .. "  " .. item.message)
        y = y + 1
    end
    term.setTextColor(colors.white)
end

local function drawLocalNodes()
    drawLocalHeader("NETWORK")
    local list = nodeBus:list()
    local _, h = term.getSize()
    local y = 5
    for _, node in ipairs(list) do
        if y >= h - 1 then break end
        term.setCursorPos(2, y)
        term.setTextColor(node.conflict and colors.red or node.localNode and colors.lime or colors.white)
        write(tostring(node.hostname or node.key))
        term.setTextColor(colors.gray)
        write("  " .. tostring(node.role or "?") .. "  cc:" .. tostring(node.computerId or "?"))
        y = y + 1
    end
    if #list == 0 then
        term.setCursorPos(2, y); term.setTextColor(colors.gray); write("(no nodes discovered)")
    end
    localButton(2, h, "Back", keys.b, "home")
    localButton(12, h, "Refresh", keys.r, "refresh")
end

local function drawLocalStorage()
    drawLocalHeader("STORAGE")
    local stats = storageState()
    term.setCursorPos(2, 5)
    if not localStore then
        term.setTextColor(colors.orange)
        print("State      : NOT INSTALLED")
        term.setTextColor(colors.gray)
        print("Install    : pkgctl install module.storage-server")
    else
        term.setTextColor(stats.available and colors.lime or colors.orange)
        print("State      : " .. (stats.available and "ACTIVE" or "DEGRADED"))
        term.setTextColor(colors.white)
        print("Backend    : " .. tostring(stats.backend or "?"))
        print("Drive      : " .. tostring(stats.drive or "-"))
        print("Disk ID    : " .. tostring(stats.diskId or "-"))
        print("File       : " .. tostring(stats.file or "-"))
        print("Namespaces : " .. tostring(stats.namespaces or 0))
        print("Keys       : " .. tostring(stats.keys or 0) .. " / " .. tostring(stats.maxKeys or "?"))
        if stats.error then term.setTextColor(colors.orange); print("Warning    : " .. tostring(stats.error)) end
    end
    local _, h = term.getSize()
    localButton(2, h, "Back", keys.b, "home")
    localButton(12, h, "Refresh", keys.r, "refresh")
end

local function drawLocalDisplay()
    drawLocalHeader("DISPLAY")
    term.setCursorPos(2, 5)
    if monitor then
        local status = display.getStatus()
        term.setTextColor(colors.lime)
        print("State      : " .. string.upper(displayState))
        term.setTextColor(colors.white)
        print("Peripheral : " .. tostring(monitorName))
        print("Resolution : " .. tostring(displayWidth) .. "x" .. tostring(displayHeight))
        print("Backend    : " .. tostring(status.backend))
        if status.error then term.setTextColor(colors.orange); print("Warning    : " .. tostring(status.error)) end
    else
        term.setTextColor(colors.orange)
        print("State      : INACTIVE")
        term.setTextColor(colors.gray)
        print("Reason     : no monitor detected")
    end
    local _, h = term.getSize()
    localButton(2, h, "Back", keys.b, "home")
    localButton(12, h, "Refresh", keys.r, "refresh")
end

local function redrawLocal()
    if localPage == "nodes" then drawLocalNodes()
    elseif localPage == "display" then drawLocalDisplay()
    else drawLocalHome() end
end

local function openHomeConfig()
    if not shell.openTab then
        notice("warn", "Home config requires multishell")
        return
    end
    local id = shell.openTab("profilectl.lua", "home")
    if id and multishell and multishell.setTitle then pcall(multishell.setTitle, id, "home-config") end
    if id and multishell and multishell.setFocus then pcall(multishell.setFocus, id) end
end

local function localAction(action)
    if action == "nodes" or action == "display" or action == "home" then
        localPage = action
    elseif action == "home_config" then
        openHomeConfig()
    elseif action == "refresh" then
        nodeBus:tick()
        refreshDisplay(true)
    end
end

local function localKey(key)
    for _, box in ipairs(localHitboxes) do
        if box.key == key then localAction(box.action); return end
    end
end

local function localMouse(x, y)
    for _, box in ipairs(localHitboxes) do
        if y == box.y and x >= box.x1 and x <= box.x2 then localAction(box.action); return end
    end
end

runtime.set("app:master", "active", { detail = "AttaCC Master active" })
runtime.log("master", "info", "AttaCC Master started")
local masterStartEvent = {
    type = "module_event", network = nodeBus.machine.network,
    machine = nodeBus.machine.key, hostname = nodeBus.machine.hostname,
    module = "core.runtime", source = nodeBus.machine.key, level = "info",
    code = "APP_START", message = "Started master", timestamp = protocol.now(),
}
pushEvent(masterStartEvent)
protocol.send(modem, config.channels.events, masterStartEvent)

modem.open(config.channels.telemetry)
modem.open(config.channels.events)
modem.open(config.channels.ack)
modem.open(config.channels.sdkSnapshot or 4259)
modem.open(config.channels.sdkAck or 4258)
if config.channels.moduleData then modem.open(config.channels.moduleData) end
if config.channels.moduleEvents then modem.open(config.channels.moduleEvents) end
if config.channels.moduleAck then modem.open(config.channels.moduleAck) end

refreshDisplay()
redraw()
broadcastPocket()
redrawLocal()

local pushTimer = os.startTimer(config.timing.masterPushSeconds)
local persistenceTimer = os.startTimer(5)
local commandTimer = os.startTimer(0.1)

while true do
    local event, p1, p2, p3, p4 = os.pullEvent()

    if event == bus.EVENT then
        bus.handle(event, p1, p2, p3)

    elseif event == "attacc_storage_request" then
        if localStore then sharedStore:handle("local", p1) end

    elseif event == "modem_message" then
        local channel, msg = p2, p4
        if net then net:handle(channel, p3, msg) end

        local nodeAction = nodeBus:handle(channel, msg)
        if channel == config.channels.nodeStatus and type(msg) == "table"
            and msg.type == "node_status" and msg.key
            and (not msg.network or msg.network == nodeBus.machine.network)
            and not knownLifecycleNodes[msg.key] then
            knownLifecycleNodes[msg.key] = true
            local onlineEvent = {
                type = "module_event", network = nodeBus.machine.network,
                machine = msg.key, hostname = msg.hostname or msg.name or msg.key,
                module = "core.runtime", source = msg.key, level = "info",
                code = "NODE_ONLINE", message = "Node announced on network",
                timestamp = protocol.now(),
            }
            pushEvent(onlineEvent)
            protocol.send(modem, config.channels.events, onlineEvent)
        end
        if nodeAction == "reboot" then sleep(0.15); os.reboot() end

        if channel == (config.channels.sdkSnapshot or 4259) and type(msg)=="table"
            and msg.network==nodeBus.machine.network then
            local compat=require("lib.sdk_snapshot").compat(msg)
            if compat then rememberControlApp(compat) end
        elseif (channel == config.channels.telemetry or channel == config.channels.moduleData)
            and type(msg) == "table"
            and (not msg.network or msg.network == nodeBus.machine.network)
        then
            rememberControlApp(msg)
        elseif (channel == config.channels.events or channel == config.channels.moduleEvents)
            and type(msg) == "table"
            and (not msg.network or msg.network == nodeBus.machine.network)
        then
            pushEvent(msg)
        elseif (channel == config.channels.ack or channel == config.channels.moduleAck
            or channel == (config.channels.sdkAck or 4258))
            and type(msg) == "table"
            and pending
            and msg.id == pending.id
        then
            if pending.sdk then
                if require("lib.sdk_commands").acceptAck(msg,pending) then
                    pending = nil
                end
            elseif channel ~= (config.channels.sdkAck or 4258) then
                pending = nil
            end
        end

    elseif event == "timer" and p1 == persistenceTimer then
        saveEvents()
        persistenceTimer = os.startTimer(5)

    elseif event == "monitor_touch" then
        if monitor and (not monitorName or p1 == monitorName) then
            local action, arg = display.actionAt(p2, p3)
            if action == "page" then
                page = arg
            elseif action == "machine_select" then
                selectApp(arg)
                page = "machine"
            elseif action == "machine_tab" then
                machineTab = arg
                machinePage = 1
            elseif action == "machine_page" then
                machinePage = tonumber(arg) or 1
            elseif action == "event_machine" and arg then
                for key,item in pairs(controlApps) do
                    if item.machine == arg then
                        selectApp(key)
                        page = "machine"
                        machinePage = 1
                        break
                    end
                end
            elseif action == "command" then
                send(arg)
            elseif action == "node_reboot" and arg then
                local id = commandId()
                local _, _, localTarget = nodeBus:sendReboot({ arg }, "master", id)
                pushEvent({
                    type = "module_event",
                    level = "warning",
                    code = "NODE_REBOOT_REQUEST",
                    message = "Reboot requested for " .. tostring(arg),
                    timestamp = protocol.now(),
                    source = "master",
                    machine = nodeBus.machine.key,
                })
                if localTarget then sleep(0.15); os.reboot() end
            end
            redraw()
        end

    elseif event == "peripheral" or event == "peripheral_detach" then
        refreshSpeaker()
        refreshDisplay(true)
        redraw()
        redrawLocal()

    elseif event == "disk" or event == "disk_eject" then
        local store = storageState()
        notice(store.available and "info" or "warn",
            event == "disk"
                and ("Storage media -> " .. (store.available and "available" or "inserted but unavailable"))
                or "Storage media -> ejected")
        redraw()
        redrawLocal()

    elseif event == "monitor_resize" then
        refreshDisplay(true)
        redraw()
        redrawLocal()

    elseif event == "key" then
        localKey(p1)
        redrawLocal()

    elseif event == "mouse_click" then
        localMouse(p2, p3)
        redrawLocal()

    elseif event == "timer" then
        if p1 == pushTimer then
            nodeBus:tick()
            refreshDisplay()
            redraw()
            broadcastPocket()

            local store = storageState()
            runtime.set("module:network.storage",
                localStore and (store.available and "active" or "degraded") or "inactive",
                { detail = store.error or tostring(store.backend or "not installed") })

            webcap.publish("master", {
                page = page,
                machineTab = machineTab,
                graphPage = graphPage,
                machines = #controlAppList(false),
                nodes = #nodeBus:list(),
                selectedApp = selectedAppKey,
                pendingCommand = pending and pending.command or nil,
                displayActive = monitor ~= nil,
                displayBackend = monitor and display.getStatus().backend or nil,
            })

            if localStore then webcap.publish("storage", store) end
            redrawLocal()
            pushTimer = os.startTimer(config.timing.masterPushSeconds)

        elseif p1 == commandTimer then
            if pending and (protocol.now() - pending.sentAt) >= config.timing.commandRetryMs then
                if pending.retries < config.timing.commandMaxRetries then
                    transmitPending()
                else
                    pushEvent({
                        type = "module_event",
                        level = "critical",
                        code = "MASTER_NO_ACK",
                        message = "No ACK for " .. tostring(pending.command),
                        timestamp = protocol.now(),
                        source = "master",
                        machine = nodeBus.machine.key,
                    })
                    pending = nil
                end
            end
            commandTimer = os.startTimer(0.1)
        end
    end
end
