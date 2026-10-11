local config = require("lib.config")
local protocol = require("lib.protocol")
local ui = require("lib.ui")

local modem = protocol.findWirelessModem()
local monitor = peripheral.find("monitor")
local speaker = peripheral.find("speaker")

if not modem then error("Wireless modem introuvable") end
if not monitor then error("Wall Monitor introuvable") end

modem.open(config.channels.telemetry)
modem.open(config.channels.events)
modem.open(config.channels.ack)

monitor.setTextScale(0.5)

local page = "dashboard"
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
        type = "steam_plant_status",
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
    local msg = protocol.makeCommand(command, "master", id, rpm and { rpm = rpm } or {})
    pending = { id = id, message = msg, command = command, sentAt = 0, retries = 0 }
    transmitPending()
end

local function redraw()
    local now = protocol.now()
    ui.draw(monitor, page, data, collectorFresh(), latestEvent, events, pending, {
        now = now,
        lastTelemetry = lastTelemetry,
        telemetryAgeMs = data and (now - lastTelemetry) or nil,
    })
end

redraw()
broadcastPocket()

local pushTimer = os.startTimer(config.timing.masterPushSeconds)
local commandTimer = os.startTimer(0.1)

while true do
    local event, p1, p2, p3, p4 = os.pullEvent()

    if event == "modem_message" then
        local channel = p2
        local msg = p4

        if channel == config.channels.telemetry and type(msg) == "table" and msg.source == "steam_plant" then
            data = msg
            lastTelemetry = protocol.now()
        elseif channel == config.channels.events and type(msg) == "table" and msg.type == "plant_event" then
            pushEvent(msg)
        elseif channel == config.channels.ack and type(msg) == "table" and msg.type == "command_ack" and pending and msg.id == pending.id then
            pending = nil
        end

    elseif event == "monitor_touch" then
        local action, arg = ui.actionAt(p2, p3)
        if action == "page" then
            page = arg
        elseif action == "command" then
            send(arg)
        end
        redraw()

    elseif event == "timer" then
        if p1 == pushTimer then
            redraw()
            broadcastPocket()
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
