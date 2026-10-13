local config = require("lib.config")
local protocol = require("lib.protocol")
local displayCore = require("lib.display")
local display = require("lib.master_display")
local nodes = require("lib.nodes")
local runtime = require("lib.runtime")
local bus = require("lib.bus")
local network = require("lib.network")
local okNetworkStore, networkStore = pcall(require, "lib.network_store")
local webcap = require("lib.webcap")

local modem = protocol.findWirelessModem()
if not modem then error("Wireless modem introuvable") end

local nodeBus = nodes.new(modem, "master")
local net = network.new(config, nodeBus.machine)
local sharedStore = okNetworkStore and networkStore.new(modem, config) or nil

local monitor = nil
local monitorName = nil
local speaker = peripheral.find("speaker")
local displayFaultReported = false

local page = ((config.master and config.master.pages and config.master.pages[1]) or "dashboard")
local data = nil
local lastTelemetry = 0
local latestEvent = nil
local events = {}
local pending = nil
local commandSeq = 1

local localPage = "home"
local localHitboxes = {}
local notices = {}
local displayWidth = nil
local displayHeight = nil
local displayState = "unknown"

local function notice(level, message)
    table.insert(notices, 1, {
        level = level or "info",
        message = tostring(message),
        at = textutils.formatTime(os.time(), true),
    })
    while #notices > 5 do table.remove(notices) end
    runtime.log("master", level == "warn" and "warning" or level, tostring(message))
end

local function collectorFresh()
    return data and (protocol.now() - lastTelemetry) < config.timing.collectorStaleMs
end

local function pushEvent(event)
    table.insert(events, 1, event)
    while #events > config.events.historySize do table.remove(events) end
    latestEvent = event

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
        if displayState ~= "inactive" then
            notice("warn", "Display -> no monitor detected")
        end
        monitor = nil
        monitorName = nil
        displayWidth = nil
        displayHeight = nil
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

    if monitor and not changedMonitor and not geometryChanged and not force then
        return true
    end

    local oldGeometry = displayWidth and (tostring(displayWidth) .. "x" .. tostring(displayHeight)) or nil

    if monitor and changedMonitor then pcall(display.shutdown, monitor) end

    local ok, status = pcall(display.init, found)
    if not ok then
        if displayState ~= "degraded" then
            notice("warn", "Display -> init failed: " .. tostring(status))
        end
        monitor = nil
        monitorName = nil
        displayWidth = nil
        displayHeight = nil
        displayState = "degraded"
        runtime.set("module:core.display", "degraded", { detail = tostring(status) })
        return false
    end

    monitor = found
    monitorName = foundName
    displayWidth = width
    displayHeight = height
    displayFaultReported = false
    displayState = status.degraded and "degraded" or "active"

    runtime.set("module:core.display", displayState, {
        device = monitorName,
        backend = status.backend,
        width = width,
        height = height,
        detail = status.error or ("master display backend " .. tostring(status.backend)),
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

local function broadcastPocket()
    protocol.send(modem, config.channels.pocketStatus, {
        type = "module_status",
        module = (config.master and config.master.sourceModule) or "steamplant",
        masterTimestamp = protocol.now(),
        collectorTimestamp = data and data.timestamp or nil,
        collectorAgeMs = data and (protocol.now() - lastTelemetry) or nil,
        collectorFresh = collectorFresh(),
        data = data,
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
    protocol.send(modem, config.channels.control, pending.message)
    pending.sentAt = protocol.now()
    pending.retries = pending.retries + 1
end

local function send(command, rpm)
    if pending then return end
    local id = commandId()
    local msg = protocol.makeModuleCommand(
        (config.master and config.master.sourceModule) or "steamplant",
        command,
        "master",
        id,
        rpm and { rpm = rpm } or {}
    )
    pending = {
        id = id,
        message = msg,
        command = command,
        sentAt = 0,
        retries = 0,
    }
    transmitPending()
end

local function redraw()
    if not monitor then return false, "display inactive" end

    local now = protocol.now()
    local ok, err = display.draw(monitor, page, data, collectorFresh(), latestEvent, events, pending, {
        now = now,
        lastTelemetry = lastTelemetry,
        telemetryAgeMs = data and (now - lastTelemetry) or nil,
        display = display.getStatus(),
        nodes = nodeBus:list(),
    })

    if ok then
        runtime.set("module:core.display", "active", {
            device = monitorName,
            backend = display.getStatus().backend,
            detail = "master display renderer active",
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
                type = "plant_event",
                level = "warning",
                code = "DISPLAY_FALLBACK",
                message = "Graphics renderer failed; text fallback active: " .. tostring(err),
                timestamp = protocol.now(),
                source = "master",
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
    table.insert(localHitboxes, {
        x1 = x,
        x2 = x + #label + 1,
        y = y,
        key = key,
        action = action,
    })
end

local function webState()
    if not fs.exists("/etc/webbridge.lua") then return "disabled", "not configured" end
    local snapshot = runtime.snapshot()
    local item = snapshot.services and snapshot.services["service:webbridge"] or nil
    return item and item.status or "starting", item and item.detail or "configured"
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
    local storeStats = sharedStore and sharedStore:stats() or nil
    local webStatus, webDetail = webState()

    term.setCursorPos(2, 5)
    term.setTextColor(colors.lightGray)
    write("Network  ")
    term.setTextColor(colors.lime)
    write("ACTIVE")
    term.setTextColor(colors.gray)
    write("  " .. tostring(#nodeList) .. " node(s)")

    term.setCursorPos(2, 6)
    term.setTextColor(colors.lightGray)
    write("Storage  ")
    if storeStats then
        term.setTextColor(colors.lime)
        write("ACTIVE")
        term.setTextColor(colors.gray)
        write("  " .. tostring(storeStats.namespaces) .. " ns / " .. tostring(storeStats.keys) .. " key(s)")
    else
        term.setTextColor(colors.orange)
        write("UNAVAILABLE")
        term.setTextColor(colors.gray)
        write("  module.storage-server not installed")
    end

    term.setCursorPos(2, 7)
    term.setTextColor(colors.lightGray)
    write("Display  ")
    if monitor then
        term.setTextColor(displayState == "active" and colors.lime or colors.orange)
        write(string.upper(displayState))
        term.setTextColor(colors.gray)
        write("  " .. tostring(monitorName) .. "  "
            .. tostring(displayWidth or "?") .. "x" .. tostring(displayHeight or "?"))
    else
        term.setTextColor(colors.orange)
        write("INACTIVE")
        term.setTextColor(colors.gray)
        write("  no monitor detected")
    end

    term.setCursorPos(2, 8)
    term.setTextColor(colors.lightGray)
    write("Web      ")
    term.setTextColor(webStatus == "active" and colors.lime
        or webStatus == "degraded" and colors.red
        or colors.orange)
    write(string.upper(tostring(webStatus)))
    term.setTextColor(colors.gray)
    write("  " .. tostring(webDetail or ""))

    term.setCursorPos(2, 10)
    term.setTextColor(colors.yellow)
    write("TOOLS")
    localButton(2, 12, "Nodes", keys.n, "nodes")
    localButton(12, 12, "Storage", keys.s, "storage")
    localButton(24, 12, "Display", keys.d, "display")
    localButton(36, 12, "Refresh", keys.r, "refresh")

    term.setCursorPos(2, 14)
    term.setTextColor(colors.yellow)
    write("RECENT")
    local y = 15
    for _, item in ipairs(notices) do
        term.setCursorPos(2, y)
        term.setTextColor(item.level == "warn" and colors.orange
            or item.level == "error" and colors.red
            or colors.lightGray)
        write(item.at .. "  " .. item.message)
        y = y + 1
    end
    term.setTextColor(colors.white)
end

local function drawLocalNodes()
    drawLocalHeader("NODES")
    local list = nodeBus:list()
    local _, h = term.getSize()
    local y = 5
    for _, node in ipairs(list) do
        if y >= h - 1 then break end
        term.setCursorPos(2, y)
        term.setTextColor(node.localNode and colors.lime or colors.white)
        write(tostring(node.hostname or node.key))
        term.setTextColor(colors.gray)
        write("  " .. tostring(node.role or "?") .. "  cc:" .. tostring(node.computerId or "?"))
        y = y + 1
    end
    if #list == 0 then
        term.setCursorPos(2, y)
        term.setTextColor(colors.gray)
        write("(no nodes discovered)")
    end
    localButton(2, h, "Back", keys.b, "home")
    localButton(12, h, "Refresh", keys.r, "refresh")
end

local function drawLocalStorage()
    drawLocalHeader("STORAGE")
    term.setCursorPos(2, 5)

    if not sharedStore then
        term.setTextColor(colors.orange)
        print("State      : UNAVAILABLE")
        term.setTextColor(colors.gray)
        print("Reason     : module.storage-server is not installed")
        print("")
        print("Install with:")
        term.setTextColor(colors.white)
        print("pkgctl install module.storage-server")
    else
        local stats = sharedStore:stats()
        term.setTextColor(colors.lime)
        print("State      : ACTIVE")
        term.setTextColor(colors.white)
        print("Namespaces : " .. tostring(stats.namespaces))
        print("Keys       : " .. tostring(stats.keys) .. " / " .. tostring(stats.maxKeys))
        print("Value limit: " .. tostring(stats.maxValueBytes) .. " bytes")
        print("Store file : " .. tostring(sharedStore.file))
        term.setTextColor(colors.gray)
        print("")
        print("Use storagectl tree/get/set/delete from the CraftOS shell.")
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
        if status.error then
            term.setTextColor(colors.orange)
            print("Warning    : " .. tostring(status.error))
        end
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
    if localPage == "nodes" then
        drawLocalNodes()
    elseif localPage == "storage" then
        drawLocalStorage()
    elseif localPage == "display" then
        drawLocalDisplay()
    else
        drawLocalHome()
    end
end

local function localAction(action)
    if action == "nodes" or action == "storage" or action == "display" or action == "home" then
        localPage = action
    elseif action == "refresh" then
        nodeBus:tick()
        refreshDisplay(true)
    end
end

local function localKey(key)
    for _, box in ipairs(localHitboxes) do
        if box.key == key then
            localAction(box.action)
            return
        end
    end
end

local function localMouse(x, y)
    for _, box in ipairs(localHitboxes) do
        if y == box.y and x >= box.x1 and x <= box.x2 then
            localAction(box.action)
            return
        end
    end
end

runtime.set("module:attacc.master", "active", {
    detail = "AttaCC master application active",
})
if sharedStore then
    runtime.set("module:network.storage", "active", {
        detail = "shared storage hosted by master application",
    })
else
    runtime.set("module:network.storage", "inactive", {
        detail = "module.storage-server not installed",
    })
end
runtime.log("master", "info", "AttaCC master started")

modem.open(config.channels.telemetry)
modem.open(config.channels.events)
modem.open(config.channels.ack)
if config.channels.moduleData then modem.open(config.channels.moduleData) end
if config.channels.moduleEvents then modem.open(config.channels.moduleEvents) end
if config.channels.moduleAck then modem.open(config.channels.moduleAck) end

refreshDisplay()
redraw()
broadcastPocket()
redrawLocal()

local pushTimer = os.startTimer(config.timing.masterPushSeconds)
local commandTimer = os.startTimer(0.1)

while true do
    local event, p1, p2, p3, p4 = os.pullEvent()

    if event == bus.EVENT then
        bus.handle(event, p1, p2, p3)

    elseif event == "attacc_storage_request" then
        if sharedStore then sharedStore:handle("local", p1) end

    elseif event == "modem_message" then
        local channel = p2
        local msg = p4

        if net then net:handle(channel, p3, msg) end
        local nodeAction = nodeBus:handle(channel, msg)
        if nodeAction == "reboot" then
            sleep(0.15)
            os.reboot()
        end

        local sourceModule = (config.master and config.master.sourceModule) or "steamplant"

        if sharedStore and sharedStore:handle(channel, msg) then
            -- handled by the optional storage module embedded in the master application
        elseif (channel == config.channels.telemetry or channel == config.channels.moduleData)
            and type(msg) == "table"
            and (msg.module == sourceModule
                or (sourceModule == "steamplant" and msg.source == "steam_plant"))
        then
            data = msg
            lastTelemetry = protocol.now()
        elseif (channel == config.channels.events or channel == config.channels.moduleEvents)
            and type(msg) == "table"
            and (msg.module == sourceModule
                or (sourceModule == "steamplant" and msg.type == "plant_event"))
        then
            pushEvent(msg)
        elseif (channel == config.channels.ack or channel == config.channels.moduleAck)
            and type(msg) == "table"
            and (msg.type == "module_ack" or msg.type == "command_ack")
            and pending
            and msg.id == pending.id
        then
            pending = nil
        end

    elseif event == "monitor_touch" then
        if monitor and (not monitorName or p1 == monitorName) then
            local action, arg = display.actionAt(p2, p3)
            if action == "page" then
                page = arg
            elseif action == "command" then
                send(arg)
            elseif action == "node_reboot" and arg then
                local id = commandId()
                local _, _, localTarget = nodeBus:sendReboot({ arg }, "master", id)
                pushEvent({
                    type = "plant_event",
                    level = "warning",
                    code = "NODE_REBOOT_REQUEST",
                    message = "Reboot requested for " .. tostring(arg),
                    timestamp = protocol.now(),
                    source = "master",
                })
                if localTarget then
                    sleep(0.15)
                    os.reboot()
                end
            end
            redraw()
        end

    elseif event == "peripheral" or event == "peripheral_detach" then
        refreshSpeaker()
        refreshDisplay(true)
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

            local discovered = nodeBus:list()
            webcap.publish("supervisor", {
                page = page,
                nodes = #discovered,
                sourceModule = (config.master and config.master.sourceModule) or "steamplant",
                sourceFresh = collectorFresh() == true,
                pendingCommand = pending and pending.command or nil,
                displayActive = monitor ~= nil,
                displayBackend = monitor and display.getStatus().backend or nil,
            })

            if sharedStore and sharedStore.stats then
                webcap.publish("storage", sharedStore:stats())
            end

            redrawLocal()
            pushTimer = os.startTimer(config.timing.masterPushSeconds)

        elseif p1 == commandTimer then
            if pending and (protocol.now() - pending.sentAt) >= config.timing.commandRetryMs then
                if pending.retries < config.timing.commandMaxRetries then
                    transmitPending()
                else
                    pushEvent({
                        type = "plant_event",
                        level = "critical",
                        code = "MASTER_NO_ACK",
                        message = "No ACK for " .. tostring(pending.command),
                        timestamp = protocol.now(),
                        source = "master",
                    })
                    pending = nil
                end
            end
            commandTimer = os.startTimer(0.1)
        end
    end
end
