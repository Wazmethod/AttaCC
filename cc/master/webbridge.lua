local config = require("lib.config")
local protocol = require("lib.protocol")

if not fs.exists("web.local.lua") then
    print("Web bridge disabled: web.local.lua missing")
    return
end

local web = dofile("web.local.lua")
if type(web) ~= "table" then error("web.local.lua must return a table") end
if not web.url or web.url == "" then error("Missing web.url in web.local.lua") end
if not web.machineToken or web.machineToken == "" then error("Missing web.machineToken in web.local.lua") end

local modem = protocol.findWirelessModem()
if not modem then error("Wireless modem introuvable") end

modem.open(config.channels.telemetry)
modem.open(config.channels.ack)
modem.open(config.channels.events)

local function connect()
    while true do
        local ws, err = http.websocket(web.url, {
            Authorization = "Bearer " .. web.machineToken,
        })

        if ws then
            print("WebSocket connected")
            return ws
        end

        print("WebSocket error: " .. tostring(err))
        sleep(web.retrySeconds or 3)
    end
end

local ws = connect()

local function wsSend(obj)
    local raw = textutils.serializeJSON(obj)
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
                modem.transmit(config.channels.control, config.channels.control, {
                    target = "steam_plant",
                    command = msg.command,
                    rpm = msg.rpm,
                    origin = "web",
                    id = msg.id,
                    timestamp = protocol.now(),
                })
            end
        end
    end
end

local function modemLoop()
    while true do
        local _, _, channel, _, message = os.pullEvent("modem_message")

        if channel == config.channels.telemetry
            and type(message) == "table"
            and message.source == "steam_plant"
        then
            wsSend({
                type = "telemetry",
                data = message,
                timestamp = protocol.now(),
            })

        elseif channel == config.channels.events
            and type(message) == "table"
            and message.type == "plant_event"
        then
            wsSend({
                type = "event",
                level = message.level,
                code = message.code,
                message = message.message,
                timestamp = message.timestamp or protocol.now(),
            })

        elseif channel == config.channels.ack
            and type(message) == "table"
            and message.type == "command_ack"
            and message.id
            and tostring(message.id):match("^web%-")
        then
            wsSend({
                type = "command_ack",
                id = message.id,
                command = message.command,
                ok = message.ok,
                error = message.error,
                timestamp = protocol.now(),
            })
        end
    end
end

parallel.waitForAny(websocketLoop, modemLoop)
