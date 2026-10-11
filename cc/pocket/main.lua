local config = require("lib.config")
local protocol = require("lib.protocol")
local display = require("lib.display")
local nodes = require("lib.nodes")

local modem = protocol.findWirelessModem()
if not modem then error("Wireless modem introuvable") end

local displayStatus = display.init()
local nodeBus = nodes.new(modem, "pocket")

modem.open(config.channels.pocketStatus)
modem.open(config.channels.ack)

local data = nil
local events = {}
local lastMasterFrame = 0
local collectorFresh = false
local page = 1

local pending = nil
local nextId = 1
local selectedNodes = {}
local rebootConfirmUntil = 0

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
    display.draw(
        page,
        data,
        events,
        masterAlive(),
        collectorFresh,
        pending ~= nil,
        t,
        c,
        nodeBus:list(),
        selectedNodes,
        protocol.now() < rebootConfirmUntil
    )
end

redraw()
local refreshTimer = os.startTimer(0.1)

while true do
    local event, p1, p2, p3, p4 = os.pullEvent()

    if event == "modem_message" then
        local channel = p2
        local msg = p4

        local nodeAction, nodeMessage = nodeBus:handle(channel, msg)
        if nodeAction == "reboot" then
            sleep(0.15)
            os.reboot()
        elseif nodeAction == "ack" then
            setToast("REBOOT ACK " .. tostring(nodeMessage.key or ""), colors.lime, 1200)
        end

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
            and (msg.type == "module_ack" or msg.type == "command_ack")
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
        local action, arg = display.click(page, data, p2, p3, nodeBus:list(), selectedNodes)

        if action == "page" then
            page = arg
        elseif action == "command" then
            sendCommand(arg.command, arg.rpm)
        elseif action == "node_toggle" then
            selectedNodes[arg] = not selectedNodes[arg]
            rebootConfirmUntil = 0
        elseif action == "node_reboot_selected" then
            local targets = {}
            for key, selected in pairs(selectedNodes) do
                if selected then table.insert(targets, key) end
            end

            if #targets == 0 then
                setToast("SELECT NODE", colors.orange, 1200)
            elseif protocol.now() < rebootConfirmUntil then
                local id = newId()
                local _, _, localTarget = nodeBus:sendReboot(targets, "pocket", id)
                rebootConfirmUntil = 0
                setToast("REBOOT SENT x" .. tostring(#targets), colors.orange, 1400)
                if localTarget then
                    sleep(0.15)
                    os.reboot()
                end
            else
                rebootConfirmUntil = protocol.now() + 3000
                setToast("TAP AGAIN TO CONFIRM", colors.red, 2500)
            end
        end
        redraw()

    elseif event == "key" then
        if p1 == keys.left then
            page = page - 1
            if page < 1 then page = display.pageCount end
        elseif p1 == keys.right then
            page = page + 1
            if page > display.pageCount then page = 1 end
        elseif p1 == keys.p then
            sendCommand("procedure")
        elseif p1 == keys.a then
            sendCommand("abort")
        end
        redraw()

    elseif event == "timer" and p1 == refreshTimer then
        nodeBus:tick()

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
