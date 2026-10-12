local config = require("lib.config")
local protocol = require("lib.protocol")
local machineInfo = require("lib.machine")
local services = require("lib.services")
local runtime = require("lib.runtime")

local modem = protocol.findWirelessModem()
if not modem then
    runtime.set("service:remote-shell", "failed", { detail = "wireless modem unavailable" })
    runtime.log("service:remote-shell", "error", "wireless modem unavailable")
    return
end

local REQUEST = config.channels.remoteShellRequest or 4257
local RESPONSE = config.channels.remoteShellResponse or 4258
local machine = machineInfo.get()
local settings = config.remoteShell or {}
local sessions = {}
local SESSION_TTL = tonumber(settings.sessionTtlMs) or 300000
local activeJob = nil

modem.open(REQUEST)

term.setTextColor(colors.lightGray)
print("Waiting for remote-shell connection...")
term.setTextColor(colors.white)

local function remoteLabel(request)
    return tostring(request.originHostname or request.origin or "unknown")
end

local function sendPacket(payload)
    protocol.send(modem, RESPONSE, payload)
end

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
    sendPacket(payload)
end

local function sendStream(job, op, data)
    data = data or {}
    data.type = "remote_shell_stream"
    data.network = machine.network
    data.machine = machine.key
    data.hostname = machine.hostname
    data.session = job.sessionId
    data.execId = job.request.id
    data.op = op
    data.timestamp = protocol.now()
    sendPacket(data)
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
    sessions[id] = { origin = origin, cwd = "/", lastSeen = protocol.now() }
    return id
end

local function pruneSessions()
    local now = protocol.now()
    for id, session in pairs(sessions) do
        if not (activeJob and activeJob.sessionId == id)
            and now - (session.lastSeen or 0) > SESSION_TTL
        then
            sessions[id] = nil
        end
    end
end

local function makeTee(job, target)
    local t = {}

    local function localCall(name, ...)
        local fn = target and target[name]
        if type(fn) == "function" then return fn(...) end
    end

    function t.write(value)
        value = tostring(value or "")
        localCall("write", value)
        sendStream(job, "write", { text = value })
    end
    function t.blit(text, fg, bg)
        text, fg, bg = tostring(text or ""), tostring(fg or ""), tostring(bg or "")
        if type(target.blit) == "function" then target.blit(text, fg, bg) else localCall("write", text) end
        sendStream(job, "blit", { text = text, fg = fg, bg = bg })
    end
    function t.clear()
        localCall("clear")
        sendStream(job, "clear")
    end
    function t.clearLine()
        localCall("clearLine")
        sendStream(job, "clearLine")
    end
    function t.getCursorPos() return localCall("getCursorPos") end
    function t.setCursorPos(x, y)
        localCall("setCursorPos", x, y)
        sendStream(job, "cursor", { x = x, y = y })
    end
    function t.setCursorBlink(value)
        localCall("setCursorBlink", value)
        sendStream(job, "blink", { value = value == true })
    end
    function t.getCursorBlink() return localCall("getCursorBlink") or false end
    function t.getSize() return localCall("getSize") end
    function t.scroll(n)
        localCall("scroll", n)
        sendStream(job, "scroll", { n = n })
    end
    function t.setTextColor(c)
        localCall("setTextColor", c)
        sendStream(job, "textColor", { color = c })
    end
    t.setTextColour = t.setTextColor
    function t.getTextColor() return localCall("getTextColor") or colors.white end
    t.getTextColour = t.getTextColor
    function t.setBackgroundColor(c)
        localCall("setBackgroundColor", c)
        sendStream(job, "backgroundColor", { color = c })
    end
    t.setBackgroundColour = t.setBackgroundColor
    function t.getBackgroundColor() return localCall("getBackgroundColor") or colors.black end
    t.getBackgroundColour = t.getBackgroundColor
    function t.isColor()
        local value = localCall("isColor")
        if value == nil then value = localCall("isColour") end
        return value ~= false
    end
    t.isColour = t.isColor
    function t.setPaletteColor(...)
        localCall("setPaletteColor", ...)
    end
    t.setPaletteColour = t.setPaletteColor
    function t.getPaletteColor(...)
        local a,b,c = localCall("getPaletteColor", ...)
        return a or 0, b or 0, c or 0
    end
    t.getPaletteColour = t.getPaletteColor

    return t
end

local function finishJob(job, ok, err)
    local session = sessions[job.sessionId]
    if session then session.lastSeen = protocol.now() end
    runtime.log("service:remote-shell", ok and "info" or "error",
        tostring(job.origin) .. " exec: " .. tostring(job.command))
    send(job.request, {
        ok = ok,
        finished = true,
        cwd = session and session.cwd or "/",
        error = err,
    })
    activeJob = nil
end

local function resumeJob(event)
    local job = activeJob
    if not job then return end
    if job.filter and job.filter ~= event[1] then return end

    local result = { coroutine.resume(job.co, table.unpack(event)) }
    if not result[1] then
        finishJob(job, false, tostring(result[2]))
        return
    end

    if coroutine.status(job.co) == "dead" then
        local commandOk = result[2]
        local execErr = result[3]
        finishJob(job, commandOk ~= false, execErr)
    else
        job.filter = result[2]
    end
end

local function startJob(request, session)
    if activeJob then
        send(request, { ok = false, error = "another remote command is already running" })
        return
    end

    local target = term.current()
    local oldDir = shell.dir()
    local job = {
        sessionId = request.session,
        request = request,
        origin = request.origin,
        command = request.command,
        filter = nil,
    }
    activeJob = job

    job.co = coroutine.create(function()
        local oldTerm = term.redirect(makeTee(job, target))
        shell.setDir(session.cwd or "/")

        local okCall, commandOk = pcall(function()
            return shell.run(request.command)
        end)

        session.cwd = shell.dir()
        shell.setDir(oldDir)
        term.redirect(oldTerm)

        if not okCall then return false, tostring(commandOk) end
        if commandOk == false then return false, "command returned failure" end
        return true
    end)

    send(request, { ok = true, started = true, session = request.session, cwd = session.cwd })
    runtime.log("service:remote-shell", "info",
        tostring(request.origin) .. " start: " .. tostring(request.command))
    resumeJob({ "infra_remote_start" })
end

runtime.set("service:remote-shell", "active", {
    detail = "interactive streaming remote shell ready",
    hostname = machine.hostname,
})
runtime.log("service:remote-shell", "info",
    "remote shell listening as " .. tostring(machine.hostname))

while true do
    local event = { os.pullEventRaw() }
    local consumed = false

    if event[1] == "modem_message"
        and event[3] == REQUEST
        and type(event[5]) == "table"
    then
        local request = event[5]
        if request.type == "remote_shell_request"
            and (not request.network or request.network == machine.network)
        then
            consumed = true

            if request.action == "discover" then
                if services.isActive("remote-shell") then send(request, { ok = true }) end

            elseif targetMatches(request.target) then
                if not services.isActive("remote-shell") then
                    send(request, { ok = false, error = "remote-shell service inactive" })
                elseif not authorized(request) then
                    send(request, { ok = false, error = "authentication failed" })
                elseif request.action == "open" then
                    local id = newSession(request.origin)
                    sessions[id].hostname = request.originHostname
                    term.setTextColor(colors.lime)
                    print("Connected from " .. remoteLabel(request))
                    term.setTextColor(colors.white)
                    send(request, { ok = true, session = id, cwd = "/" })
                elseif request.action == "close" then
                    if activeJob and activeJob.sessionId == request.session then
                        resumeJob({ "terminate" })
                    end
                    local closing = sessions[request.session]
                    sessions[request.session] = nil
                    term.setTextColor(colors.yellow)
                    print("Disconnected from " .. tostring((closing and closing.hostname) or request.originHostname or request.origin or "remote"))
                    term.setTextColor(colors.lightGray)
                    print("Waiting for remote-shell connection...")
                    term.setTextColor(colors.white)
                    send(request, { ok = true })
                elseif request.action == "exec" then
                    local session = sessions[request.session]
                    if not session or session.origin ~= request.origin then
                        send(request, { ok = false, error = "invalid session" })
                    elseif type(request.command) ~= "string" or request.command == "" then
                        send(request, { ok = false, error = "empty command" })
                    else
                        session.lastSeen = protocol.now()
                        startJob(request, session)
                    end
                elseif request.action == "input" then
                    local session = sessions[request.session]
                    if session and session.origin == request.origin
                        and activeJob and activeJob.sessionId == request.session
                        and type(request.event) == "table"
                    then
                        session.lastSeen = protocol.now()
                        resumeJob(request.event)
                    end
                end
            end
        end
    end

    if activeJob and not consumed then
        resumeJob(event)
    end

    pruneSessions()
end
