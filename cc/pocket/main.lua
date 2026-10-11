local config = require("lib.config")
local protocol = require("lib.protocol")
local ui = require("lib.ui")

local modem = protocol.findWirelessModem()
if not modem then error("Wireless modem introuvable") end

modem.open(config.channels.pocketStatus)
modem.open(config.channels.ack)

local data = nil
local events = {}
local lastMasterFrame = 0
local collectorFresh = false
local page = 1

local pending = nil
local nextId = 1

local toast = nil
local toastColor = colors.white
local toastUntil = 0

local function masterAlive()
    return lastMasterFrame > 0
        and (protocol.now() - lastMasterFrame) < config.timing.masterTimeoutMs
end

local function setToast(msg, color, durationMs)
    toast = msg
    toastColor = color or colors.white
    toastUntil = protocol.now() + (durationMs or 1500)
end

local function getToast()
    if toast and protocol.now() < toastUntil then
        return toast, toastColor
    end
    return nil, nil
end

local function newId()
    local id = tostring(os.getComputerID())
        .. "-" .. tostring(protocol.now())
        .. "-" .. tostring(nextId)
    nextId = nextId + 1
    return id
end

local function transmitPending()
    if not pending then return end
    protocol.send(modem, config.channels.control, pending.message)
    pending.sentAt = protocol.now()
    pending.retries = pending.retries + 1
end

local function sendCommand(command, rpm)
    if pending then
        setToast("WAIT ACK", colors.orange, 700)
        return
    end

    local id = newId()
    local msg = protocol.makeCommand(
        command,
        "pocket",
        id,
        rpm and { rpm = rpm } or {}
    )

    pending = {
        id = id,
        command = command,
        message = msg,
        sentAt = 0,
        retries = 0,
    }

    transmitPending()
    setToast("TX " .. command, colors.lightBlue, 900)
end

local function redraw()
    local t, c = getToast()
    ui.draw(
        page,
        data,
        events,
        masterAlive(),
        collectorFresh,
        pending ~= nil,
        t,
        c
    )
end

redraw()
local refreshTimer = os.startTimer(0.1)

while true do
    local event, p1, p2, p3, p4 = os.pullEvent()

    if event == "modem_message" then
        local channel = p2
        local msg = p4

        if channel == config.channels.pocketStatus
            and type(msg) == "table"
            and msg.type == "steam_plant_status"
        then
            lastMasterFrame = protocol.now()
            collectorFresh = msg.collectorFresh and true or false

            if msg.data then data = msg.data end
            if msg.events then events = msg.events end

            redraw()

        elseif channel == config.channels.ack
            and type(msg) == "table"
            and msg.type == "command_ack"
            and pending
            and msg.id == pending.id
        then
            if msg.ok then
                setToast("ACK " .. tostring(msg.command), colors.lime, 1000)
            else
                setToast("ERR " .. tostring(msg.error), colors.red, 2200)
            end
            pending = nil
            redraw()
        end

    elseif event == "mouse_click" then
        local command, rpm = ui.click(page, data, p2, p3)
        if command then sendCommand(command, rpm) end
        redraw()

    elseif event == "key" then
        if p1 == keys.left then
            page = page - 1
            if page < 1 then page = ui.pageCount end
        elseif p1 == keys.right then
            page = page + 1
            if page > ui.pageCount then page = 1 end
        elseif p1 == keys.p then
            sendCommand("procedure")
        elseif p1 == keys.a then
            sendCommand("abort")
        end
        redraw()

    elseif event == "timer" and p1 == refreshTimer then
        if pending
            and (protocol.now() - pending.sentAt) >= config.timing.commandRetryMs
        then
            if pending.retries < config.timing.commandMaxRetries then
                transmitPending()
                setToast("RETRY " .. tostring(pending.retries), colors.orange, 500)
            else
                setToast("NO ACK", colors.red, 2200)
                pending = nil
            end
        end

        redraw()
        refreshTimer = os.startTimer(0.1)
    end
end
