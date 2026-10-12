local config = require("lib.config")
local protocol = require("lib.protocol")
local machineInfo = require("lib.machine")
local paths = require("lib.paths")

local args = { ... }
local REQUEST = config.channels.remoteShellRequest or 4257
local RESPONSE = config.channels.remoteShellResponse or 4258
local CACHE_FILE = fs.combine(paths.runtime, "hosts.json")
local HOST_NAMESPACE = "infra.hosts"

local function writeJson(path, value)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local raw = textutils.serializeJSON(value)
    local h = fs.open(path, "w")
    if h then h.write(raw) h.close() end
end

local function readCache()
    if not fs.exists(CACHE_FILE) then return { hosts = {} } end
    local h = fs.open(CACHE_FILE, "r")
    if not h then return { hosts = {} } end
    local raw = h.readAll()
    h.close()
    local ok, data = pcall(textutils.unserializeJSON, raw)
    if ok and type(data) == "table" then
        data.hosts = type(data.hosts) == "table" and data.hosts or {}
        return data
    end
    return { hosts = {} }
end

local function nextId(prefix)
    return (prefix or "ssh") .. "-" .. tostring(os.getComputerID()) .. "-"
        .. tostring(os.epoch("utc")) .. "-" .. tostring(math.random(1000,9999))
end

local modem = protocol.findWirelessModem()
if not modem then error("Wireless modem unavailable") end
modem.open(RESPONSE)

local localMachine = machineInfo.get()
local token = config.remoteShell and config.remoteShell.token or nil

local function baseMessage(action, target)
    return {
        type = "remote_shell_request",
        action = action,
        id = nextId(action),
        network = localMachine.network,
        origin = localMachine.key,
        originHostname = localMachine.hostname,
        target = target,
        token = token,
        timestamp = protocol.now(),
    }
end

local function request(message, timeout)
    protocol.send(modem, REQUEST, message)
    local timer = os.startTimer(timeout or 3)
    while true do
        local event = { os.pullEventRaw() }
        if event[1] == "timer" and event[2] == timer then return nil, "timeout" end
        if event[1] == "modem_message"
            and event[3] == RESPONSE
            and type(event[5]) == "table"
            and event[5].type == "remote_shell_response"
            and event[5].id == message.id
        then
            return event[5]
        end
    end
end

local function storageClient()
    local ok, client = pcall(require, "lib.storage_client")
    if ok then return client end
    return nil
end

local function syncFromStorage(hosts)
    local storage = storageClient()
    if not storage then return 0 end
    local keys = storage.list(HOST_NAMESPACE, 2)
    if type(keys) ~= "table" then return 0 end

    local count = 0
    for _, key in ipairs(keys) do
        local value = storage.get(HOST_NAMESPACE, key, 2)
        if type(value) == "table" then
            hosts[key] = value
            count = count + 1
        end
    end
    return count
end

local function syncToStorage(hosts)
    local storage = storageClient()
    if not storage then return 0 end

    local count = 0
    for hostname, value in pairs(hosts) do
        local ok = storage.set(HOST_NAMESPACE, hostname, value, 2)
        if ok ~= nil then count = count + 1 end
    end
    return count
end

local function saveHosts(hosts)
    writeJson(CACHE_FILE, { updatedAt = protocol.now(), hosts = hosts })
end

local function scan()
    local cache = readCache()
    local hosts = cache.hosts
    local shared = syncFromStorage(hosts)

    local id = nextId("scan")
    protocol.send(modem, REQUEST, {
        type = "remote_shell_request",
        action = "discover",
        id = id,
        network = localMachine.network,
        origin = localMachine.key,
        originHostname = localMachine.hostname,
        timestamp = protocol.now(),
    })

    local timer = os.startTimer(2)
    local direct = 0
    while true do
        local event = { os.pullEventRaw() }
        if event[1] == "timer" and event[2] == timer then break end
        if event[1] == "modem_message"
            and event[3] == RESPONSE
            and type(event[5]) == "table"
        then
            local p = event[5]
            if p.type == "remote_shell_response"
                and p.id == id and p.action == "discover" and p.ok
            then
                local hostname = p.hostname or p.machine or tostring(p.computerId)
                hosts[hostname] = {
                    hostname = p.hostname,
                    machine = p.machine,
                    computerId = p.computerId,
                    label = p.label,
                    lastSeen = protocol.now(),
                }
                direct = direct + 1
            end
        end
    end

    saveHosts(hosts)
    local pushed = syncToStorage(hosts)

    local names = {}
    for name in pairs(hosts) do table.insert(names, name) end
    table.sort(names)

    for _, name in ipairs(names) do
        local h = hosts[name]
        print(string.format("%-24s  %s  cc:%s",
            tostring(name), tostring(h.machine or "?"), tostring(h.computerId or "?")))
    end
    print(string.format("%d direct, %d shared, %d stored", direct, shared, pushed))
end

if args[1] == "--scan" or args[1] == "scan" or args[1] == "--sync" then
    scan()
    return
end

local target = args[1]
if not target or target == "" then
    print("Usage:")
    print("  ssh <hostname>")
    print("  ssh --scan")
    print("  ssh --sync")
    return
end

local openReq = baseMessage("open", target)
local response, err = request(openReq, 4)
if not response then error("Unable to connect to " .. target .. ": " .. tostring(err)) end
if not response.ok then error(response.error or "connection refused") end

local session = response.session
local hostname = response.hostname or target
local cwd = response.cwd or "/"
local history = {}

local function sendInput(ev)
    local req = baseMessage("input", target)
    req.session = session
    req.event = ev
    protocol.send(modem, REQUEST, req)
end

local function applyStream(p)
    local op = p.op
    if op == "write" then
        write(p.text or "")
    elseif op == "blit" then
        local ok = pcall(term.blit, p.text or "", p.fg or "", p.bg or "")
        if not ok then write(p.text or "") end
    elseif op == "clear" then
        term.clear()
    elseif op == "clearLine" then
        term.clearLine()
    elseif op == "cursor" then
        term.setCursorPos(tonumber(p.x) or 1, tonumber(p.y) or 1)
    elseif op == "blink" then
        term.setCursorBlink(p.value == true)
    elseif op == "scroll" then
        term.scroll(tonumber(p.n) or 0)
    elseif op == "textColor" and p.color then
        pcall(term.setTextColor, p.color)
    elseif op == "backgroundColor" and p.color then
        pcall(term.setBackgroundColor, p.color)
    end
end

local function execStreaming(command)
    local req = baseMessage("exec", target)
    req.session = session
    req.command = command
    protocol.send(modem, REQUEST, req)

    local started = false
    while true do
        local event = { os.pullEventRaw() }

        if event[1] == "modem_message"
            and event[3] == RESPONSE
            and type(event[5]) == "table"
        then
            local p = event[5]
            if p.type == "remote_shell_stream"
                and p.session == session and p.execId == req.id
            then
                applyStream(p)
            elseif p.type == "remote_shell_response" and p.id == req.id then
                if p.started then
                    started = true
                    cwd = p.cwd or cwd
                elseif p.finished then
                    cwd = p.cwd or cwd
                    if not p.ok and p.error then printError(p.error) end
                    return p.ok ~= false
                elseif not p.ok then
                    printError(p.error or "remote command failed")
                    return false
                end
            end

        elseif event[1] == "char" or event[1] == "key" or event[1] == "key_up"
            or event[1] == "paste" or event[1] == "mouse_click"
            or event[1] == "mouse_up" or event[1] == "mouse_drag"
            or event[1] == "mouse_scroll" or event[1] == "terminate"
        then
            if started then sendInput(event) end
        end
    end
end

print("Connected to " .. tostring(hostname)
    .. " (" .. tostring(response.machine or "?") .. ")")
print("Infra remote shell - streamed output/input active.")
print("Type 'exit' to disconnect.")

while true do
    term.setTextColor(colors.lime)
    write(tostring(hostname) .. ":" .. tostring(cwd) .. "$ ")
    term.setTextColor(colors.white)
    local line = read(nil, history)
    if line == nil then line = "" end

    if line ~= "" then
        table.insert(history, line)
        if #history > 50 then table.remove(history, 1) end
    end

    if line == "exit" or line == "logout" then
        local req = baseMessage("close", target)
        req.session = session
        request(req, 1)
        print("Disconnected.")
        return
    elseif line ~= "" then
        execStreaming(line)
    end
end
