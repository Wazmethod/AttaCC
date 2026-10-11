local config = require("lib.config")
local protocol = require("lib.protocol")
local machineInfo = require("lib.machine")
local services = require("lib.services")
local runtime = require("lib.runtime")

local modem = protocol.findWirelessModem()
if not modem then
    runtime.log("service:remote-shell", "error", "wireless modem unavailable")
    return
end

local REQUEST = config.channels.remoteShellRequest or 4257
local RESPONSE = config.channels.remoteShellResponse or 4258
local machine = machineInfo.get()
local settings = config.remoteShell or {}
local sessions = {}
local SESSION_TTL = tonumber(settings.sessionTtlMs) or 300000
local MAX_OUTPUT = tonumber(settings.maxOutputBytes) or 6000

modem.open(REQUEST)

local function send(request, payload)
    payload = payload or {}
    payload.type = "remote_shell_response"
    payload.id = request.id
    payload.action = request.action
    payload.network = machine.network
    payload.machine = machine.key
    payload.hostname = machine.hostname
    payload.computerId = machine.computerId
    payload.label = machine.label
    payload.timestamp = protocol.now()
    protocol.send(modem, RESPONSE, payload)
end

local function targetMatches(target)
    if not target or target == "" then return false end
    target = tostring(target)
    return target == tostring(machine.hostname)
        or target == tostring(machine.key)
        or target == tostring(machine.physicalIdentity)
        or target == tostring(machine.computerId)
end

local function authorized(request)
    local expected = settings.token
    if not expected or expected == "" then return true end
    return request.token == expected
end

local function newSession(origin)
    local id = "rs-" .. tostring(machine.computerId) .. "-"
        .. tostring(protocol.now()) .. "-" .. tostring(math.random(1000,9999))
    sessions[id] = {
        origin = origin,
        cwd = "/",
        lastSeen = protocol.now(),
    }
    return id
end

local function pruneSessions()
    local now = protocol.now()
    for id, session in pairs(sessions) do
        if now - (session.lastSeen or 0) > SESSION_TTL then
            sessions[id] = nil
        end
    end
end

local function memoryTerm(width, height)
    width = width or 100
    height = height or 40
    local lines = {}
    local x, y = 1, 1
    local textColor, bgColor = colors.white, colors.black

    local function getLine(row)
        return lines[row] or ""
    end

    local function put(text)
        text = tostring(text or "")
        local line = getLine(y)
        if #line < x - 1 then line = line .. string.rep(" ", x - 1 - #line) end
        local before = line:sub(1, x - 1)
        local after = line:sub(x + #text)
        line = before .. text .. after
        lines[y] = line
        x = x + #text
    end

    local t = {}
    function t.write(text) put(text) end
    function t.blit(text) put(text) end
    function t.clear() lines = {} x, y = 1, 1 end
    function t.clearLine() lines[y] = "" x = 1 end
    function t.getCursorPos() return x, y end
    function t.setCursorPos(nx, ny)
        x = math.max(1, math.floor(tonumber(nx) or 1))
        y = math.max(1, math.min(height, math.floor(tonumber(ny) or 1)))
    end
    function t.setCursorBlink() end
    function t.getCursorBlink() return false end
    function t.getSize() return width, height end
    function t.scroll(n)
        n = math.floor(tonumber(n) or 0)
        if n > 0 then
            for _ = 1, n do
                table.remove(lines, 1)
                table.insert(lines, "")
            end
        end
    end
    function t.setTextColor(c) textColor = c end
    t.setTextColour = t.setTextColor
    function t.getTextColor() return textColor end
    t.getTextColour = t.getTextColor
    function t.setBackgroundColor(c) bgColor = c end
    t.setBackgroundColour = t.setBackgroundColor
    function t.getBackgroundColor() return bgColor end
    t.getBackgroundColour = t.getBackgroundColor
    function t.isColor() return true end
    t.isColour = t.isColor
    function t.setPaletteColor() end
    t.setPaletteColour = t.setPaletteColor
    function t.getPaletteColor() return 0, 0, 0 end
    t.getPaletteColour = t.getPaletteColor

    function t.contents()
        local last = 0
        for i = 1, height do
            if lines[i] and lines[i] ~= "" then last = i end
        end
        local out = {}
        for i = 1, last do table.insert(out, lines[i] or "") end
        return table.concat(out, "\n")
    end

    return t
end

local function execute(session, command)
    local capture = memoryTerm(100, 50)
    local oldTerm = term.redirect(capture)
    local oldDir = shell.dir()
    local ok, err

    shell.setDir(session.cwd or "/")
    ok, err = pcall(function()
        local success = shell.run(command)
        if success == false then return false end
        return true
    end)
    session.cwd = shell.dir()
    shell.setDir(oldDir)
    term.redirect(oldTerm)

    local output = capture.contents()
    if #output > MAX_OUTPUT then
        output = output:sub(1, MAX_OUTPUT) .. "\n[output truncated]"
    end

    if not ok then return false, output, tostring(err) end
    return true, output
end

runtime.log("service:remote-shell", "info",
    "remote shell listening as " .. tostring(machine.hostname))

while true do
    local event, p1, p2, p3, p4 = os.pullEvent()
    if event == "modem_message" and p2 == REQUEST and type(p4) == "table" then
        local request = p4
        if request.type == "remote_shell_request"
            and (not request.network or request.network == machine.network)
        then
            if request.action == "discover" then
                if services.isActive("remote-shell") then
                    send(request, { ok = true })
                end
            elseif targetMatches(request.target) then
                if not services.isActive("remote-shell") then
                    send(request, { ok = false, error = "remote-shell service inactive" })
                elseif not authorized(request) then
                    send(request, { ok = false, error = "authentication failed" })
                elseif request.action == "open" then
                    local id = newSession(request.origin)
                    runtime.log("service:remote-shell", "info",
                        "session opened from " .. tostring(request.origin))
                    send(request, { ok = true, session = id, cwd = "/" })
                elseif request.action == "close" then
                    sessions[request.session] = nil
                    send(request, { ok = true })
                elseif request.action == "exec" then
                    local session = sessions[request.session]
                    if not session or session.origin ~= request.origin then
                        send(request, { ok = false, error = "invalid session" })
                    elseif type(request.command) ~= "string" or request.command == "" then
                        send(request, { ok = false, error = "empty command" })
                    else
                        session.lastSeen = protocol.now()
                        local okExec, output, execErr = execute(session, request.command)
                        runtime.log("service:remote-shell", okExec and "info" or "error",
                            tostring(request.origin) .. " exec: " .. tostring(request.command))
                        send(request, {
                            ok = okExec,
                            output = output,
                            cwd = session.cwd,
                            error = execErr,
                        })
                    end
                end
            end
        end
    end
    pruneSessions()
end
