local config = require("lib.config")
local protocol = require("lib.protocol")
local displayCore = require("lib.display")
local display = require("lib.pocket_display")
local bus = require("lib.bus")
local network = require("lib.network")
local nodes = require("lib.nodes")
local runtime = require("lib.runtime")

local modem = protocol.findWirelessModem()
if not modem then error("Wireless modem introuvable") end

local displayStatus = display.init()
local nodeBus = nodes.new(modem, "pocket")
local net = network.new(config, nodeBus.machine)

local externalMonitor, externalMonitorName = displayCore.find("auto")
if externalMonitor then
    local w, h = displayCore.geometry(externalMonitor)
    runtime.set("module:core.display", "active", {
        device = externalMonitorName,
        width = w,
        height = h,
        detail = "optional external display available",
    })
else
    runtime.set("module:core.display", "inactive", {
        detail = tostring(externalMonitorName or "no monitor detected"),
    })
end

runtime.set("module:attacc.pocket", "active", {
    detail = "AttaCC pocket application active",
})
runtime.log("pocket", "info", "AttaCC pocket client started")

modem.open(config.channels.pocketStatus)
modem.open(config.channels.ack)
if config.channels.moduleData then modem.open(config.channels.moduleData) end
if config.channels.moduleEvents then modem.open(config.channels.moduleEvents) end

local data = nil
local apps = {}
local selectedAppKey = nil
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

local function chooseApp(key)
    if type(apps) ~= "table" or #apps == 0 then
        selectedAppKey = nil
        return false
    end

    local chosen = nil
    if key then
        for _, app in ipairs(apps) do
            if app.key == key then chosen = app break end
        end
    end

    if not chosen and selectedAppKey then
        for _, app in ipairs(apps) do
            if app.key == selectedAppKey then chosen = app break end
        end
    end

    if not chosen then
        local preferred = (config.pocket and config.pocket.sourceModule) or "steamplant"
        for _, app in ipairs(apps) do
            if app.module == preferred then chosen = app break end
        end
    end

    chosen = chosen or apps[1]
    selectedAppKey = chosen and chosen.key or nil
    data = chosen and chosen.data or data
    return chosen ~= nil
end

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

local function selectedApp()
    if selectedAppKey then
        for _, app in ipairs(apps or {}) do
            if app.key == selectedAppKey then return app end
        end
    end
    return nil
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

local function sendCommand(control, rpm)
    if pending then
        setToast("WAIT ACK", colors.orange, 700)
        return
    end

    local command
    local args = {}

    if type(control) == "table" then
        command = control.command
        if type(control.args) == "table" then
            for k,v in pairs(control.args) do args[k]=v end
        end
        if control.rpm ~= nil then args.rpm = control.rpm end
    else
        command = control
        if rpm ~= nil then args.rpm = rpm end
    end

    if not command then
        setToast("INVALID ACTION", colors.red, 1200)
        return
    end

    local app = selectedApp()
    local moduleId = app and app.module
        or (config.pocket and config.pocket.sourceModule)
        or "steamplant"
    local targetMachine = app and app.machine or nil

    local id = newId()
    local msg = protocol.makeModuleCommand(
        moduleId,
        command,
        "pocket",
        id,
        args,
        targetMachine
    )

    pending = {
        id = id,
        command = command,
        module = moduleId,
        targetMachine = targetMachine,
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
        protocol.now() < rebootConfirmUntil,
        apps,
        selectedAppKey
    )
end

redraw()
local refreshTimer = os.startTimer(0.1)

while true do
    local event, p1, p2, p3, p4 = os.pullEvent()

    if event == bus.EVENT then
        bus.handle(event, p1, p2, p3)

    elseif event == "modem_message" then
        local channel = p2
        local msg = p4
        if net then net:handle(channel, p3, msg) end

        local nodeAction, nodeMessage = nodeBus:handle(channel, msg)
        if nodeAction == "reboot" then
            sleep(0.15)
            os.reboot()
        elseif nodeAction == "ack" then
            setToast("REBOOT ACK " .. tostring(nodeMessage.key or ""), colors.lime, 1200)
        end

        local transport = (config.pocket and config.pocket.transport) or "master"
        local sourceModule = (config.pocket and config.pocket.sourceModule) or "steamplant"

        if transport == "master"
            and channel == config.channels.pocketStatus
            and type(msg) == "table"
            and (msg.module == nil or msg.module == sourceModule)
            and (msg.type == "steam_plant_status" or msg.type == "module_status")
        then
            lastMasterFrame = protocol.now()
            collectorFresh = msg.collectorFresh and true or false

            if type(msg.apps) == "table" then
                apps = msg.apps
                chooseApp()
            elseif msg.data then
                data = msg.data
            end
            if msg.events then events = msg.events end

            redraw()

        elseif transport == "direct"
            and type(msg) == "table"
            and msg.module == sourceModule
            and (channel == config.channels.moduleData or channel == config.channels.telemetry)
            and (not msg.network or msg.network == nodeBus.machine.network)
        then
            data = msg
            lastMasterFrame = protocol.now()
            collectorFresh = true
            redraw()

        elseif transport == "direct"
            and type(msg) == "table"
            and msg.module == sourceModule
            and (channel == config.channels.moduleEvents or channel == config.channels.events)
            and (not msg.network or msg.network == nodeBus.machine.network)
        then
            table.insert(events, 1, msg)
            while #events > ((config.events and config.events.historySize) or 30) do
                table.remove(events)
            end
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
        local action, arg = display.click(
            page, data, p2, p3, nodeBus:list(), selectedNodes, apps, selectedAppKey
        )

        if action == "page" then
            page = arg
        elseif action == "command" then
            sendCommand(arg)
        elseif action == "app_select" then
            if chooseApp(arg) then
                page = 1
                setToast("SELECT " .. tostring(selectedAppKey), colors.cyan, 900)
            end
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
            if page < 1 then page = display.pageCount(data) end
        elseif p1 == keys.right then
            page = page + 1
            if page > display.pageCount(data) then page = 1 end
        elseif p1 == keys.p then
            sendCommand("procedure")
        elseif p1 == keys.a then
            sendCommand("abort")
        end
        redraw()

    elseif event == "peripheral" or event == "peripheral_detach" or event == "monitor_resize" then
        local mon, nameOrErr = displayCore.find("auto")
        if mon then
            local w, h = displayCore.geometry(mon)
            runtime.set("module:core.display", "active", {
                device = nameOrErr,
                width = w,
                height = h,
                detail = "optional external display available",
            })
        else
            runtime.set("module:core.display", "inactive", {
                detail = tostring(nameOrErr or "no monitor detected"),
            })
        end

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
