local config = require("lib.config")
local protocol = require("lib.protocol")
local display = require("lib.display")
local nodes = require("lib.nodes")
local runtime = require("lib.runtime")
local services = require("lib.services")
local networkStore = require("lib.network_store")

local modem = protocol.findWirelessModem()
local monitor = peripheral.find("monitor")
local speaker = peripheral.find("speaker")

if not modem then error("Wireless modem introuvable") end
if not monitor then error("Wall Monitor introuvable") end

local displayStatus = display.init(monitor)
local nodeBus = nodes.new(modem, "master")
local sharedStore = networkStore.new(modem, config)

services.syncRuntime()
runtime.set("module:core.display", displayStatus.degraded and "degraded" or "active", {
    backend = displayStatus.backend,
    detail = displayStatus.error or ("master display backend " .. tostring(displayStatus.backend)),
})
runtime.log("service:supervisor", "info", "supervisor runtime started")

modem.open(config.channels.telemetry)
modem.open(config.channels.events)
modem.open(config.channels.ack)
if config.channels.moduleData then modem.open(config.channels.moduleData) end
if config.channels.moduleEvents then modem.open(config.channels.moduleEvents) end
if config.channels.moduleAck then modem.open(config.channels.moduleAck) end

local page = ((config.master and config.master.pages and config.master.pages[1]) or "dashboard")
local data = nil
local lastTelemetry = 0
local latestEvent = nil
local events = {}
local pending = nil
local commandSeq = 1

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
    local id = "master-" .. tostring(os.getComputerID()) .. "-" .. tostring(protocol.now()) .. "-" .. tostring(commandSeq)
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
    pending = { id = id, message = msg, command = command, sentAt = 0, retries = 0 }
    transmitPending()
end

local displayFaultReported = false

local function redraw()
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
            backend = display.getStatus().backend,
            detail = "master display renderer active",
        })
    else
        runtime.set("module:core.display", "degraded", {
            backend = display.getStatus().backend,
            detail = tostring(err),
        })
    end

    if not ok and not displayFaultReported then
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

pushEvent({
    type = "plant_event",
    level = displayStatus.degraded and "warning" or "success",
    code = displayStatus.backend == "ccgraphics" and "DISPLAY_CCGRAPHICS" or "DISPLAY_TEXT",
    message = displayStatus.backend == "ccgraphics"
        and "CC:Graphics renderer active"
        or (displayStatus.error
            and ("Text renderer active; graphics unavailable: " .. tostring(displayStatus.error))
            or "Text renderer active"),
    timestamp = protocol.now(),
    source = "master",
})

redraw()
broadcastPocket()

local pushTimer = os.startTimer(config.timing.masterPushSeconds)
local commandTimer = os.startTimer(0.1)

while true do
    local event, p1, p2, p3, p4 = os.pullEvent()

    if event == "modem_message" then
        local channel = p2
        local msg = p4

        local nodeAction = nodeBus:handle(channel, msg)
        if nodeAction == "reboot" then
            sleep(0.15)
            os.reboot()
        end

        local sourceModule = (config.master and config.master.sourceModule) or "steamplant"

        if services.isActive("storage") and sharedStore:handle(channel, msg) then
            -- handled by network.storage
        elseif (channel == config.channels.telemetry or channel == config.channels.moduleData)
            and type(msg) == "table"
            and (msg.module == sourceModule or (sourceModule == "steamplant" and msg.source == "steam_plant"))
        then
            data = msg
            lastTelemetry = protocol.now()
        elseif (channel == config.channels.events or channel == config.channels.moduleEvents)
            and type(msg) == "table"
            and (msg.module == sourceModule or (sourceModule == "steamplant" and msg.type == "plant_event"))
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

    elseif event == "timer" then
        if p1 == pushTimer then
            if services.isActive("network") then nodeBus:tick() end
            services.syncRuntime()
            if services.isActive("display") then redraw() end
            if services.isActive("supervisor") then broadcastPocket() end
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
