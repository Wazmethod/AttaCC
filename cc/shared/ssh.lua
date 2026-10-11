local config = require("lib.config")
local protocol = require("lib.protocol")
local machineInfo = require("lib.machine")

local args = { ... }
local REQUEST = config.channels.remoteShellRequest or 4257
local RESPONSE = config.channels.remoteShellResponse or 4258
local CACHE_FILE = ".infra/runtime/hosts.json"

local function writeJson(path, value)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local raw = textutils.serializeJSON(value)
    local h = fs.open(path, "w")
    if h then h.write(raw) h.close() end
end

local function request(modem, message, timeout)
    modem.open(RESPONSE)
    protocol.send(modem, REQUEST, message)
    local timer = os.startTimer(timeout or 3)
    while true do
        local event, p1, p2, p3, p4 = os.pullEvent()
        if event == "timer" and p1 == timer then return nil, "timeout" end
        if event == "modem_message"
            and p2 == RESPONSE
            and type(p4) == "table"
            and p4.type == "remote_shell_response"
            and p4.id == message.id
        then
            return p4
        end
    end
end

local function nextId(prefix)
    return (prefix or "ssh") .. "-" .. tostring(os.getComputerID()) .. "-"
        .. tostring(os.epoch("utc")) .. "-" .. tostring(math.random(1000,9999))
end

local modem = protocol.findWirelessModem()
if not modem then error("Wireless modem unavailable") end
local localMachine = machineInfo.get()

if args[1] == "--scan" or args[1] == "scan" then
    modem.open(RESPONSE)
    local id = nextId("scan")
    protocol.send(modem, REQUEST, {
        type = "remote_shell_request",
        action = "discover",
        id = id,
        network = localMachine.network,
        origin = localMachine.key,
        timestamp = protocol.now(),
    })

    local timer = os.startTimer(2)
    local hosts = {}
    while true do
        local event, p1, p2, p3, p4 = os.pullEvent()
        if event == "timer" and p1 == timer then break end
        if event == "modem_message"
            and p2 == RESPONSE
            and type(p4) == "table"
            and p4.type == "remote_shell_response"
            and p4.id == id
            and p4.action == "discover"
            and p4.ok
        then
            hosts[p4.hostname or p4.machine or tostring(p4.computerId)] = {
                hostname = p4.hostname,
                machine = p4.machine,
                computerId = p4.computerId,
                label = p4.label,
            }
        end
    end

    local names = {}
    for name in pairs(hosts) do table.insert(names, name) end
    table.sort(names)
    writeJson(CACHE_FILE, { updatedAt = protocol.now(), hosts = hosts })

    if #names == 0 then
        print("No remote-shell hosts discovered.")
    else
        for _, name in ipairs(names) do
            local h = hosts[name]
            print(string.format("%-24s  %s  cc:%s",
                tostring(name),
                tostring(h.machine or "?"),
                tostring(h.computerId or "?")))
        end
    end
    return
end

local target = args[1]
if not target or target == "" then
    print("Usage:")
    print("  ssh <hostname>")
    print("  ssh --scan")
    return
end

local token = config.remoteShell and config.remoteShell.token or nil
local openId = nextId("open")
local response, err = request(modem, {
    type = "remote_shell_request",
    action = "open",
    id = openId,
    network = localMachine.network,
    origin = localMachine.key,
    target = target,
    token = token,
    timestamp = protocol.now(),
}, 4)

if not response then error("Unable to connect to " .. target .. ": " .. tostring(err)) end
if not response.ok then error(response.error or "connection refused") end

local session = response.session
local hostname = response.hostname or target
local cwd = response.cwd or "/"
local history = {}

print("Connected to " .. tostring(hostname)
    .. " (" .. tostring(response.machine or "?") .. ")")
print("Infra remote shell - type 'exit' to disconnect.")
print("Note: transport is CC modem messaging, not encrypted SSH.")

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
        local id = nextId("close")
        request(modem, {
            type = "remote_shell_request",
            action = "close",
            id = id,
            network = localMachine.network,
            origin = localMachine.key,
            target = target,
            session = session,
            token = token,
            timestamp = protocol.now(),
        }, 1)
        print("Disconnected.")
        return
    end

    if line ~= "" then
        local id = nextId("exec")
        local reply, execErr = request(modem, {
            type = "remote_shell_request",
            action = "exec",
            id = id,
            network = localMachine.network,
            origin = localMachine.key,
            target = target,
            session = session,
            command = line,
            token = token,
            timestamp = protocol.now(),
        }, 15)

        if not reply then
            printError("Remote shell timeout: " .. tostring(execErr))
        elseif not reply.ok then
            printError(reply.error or "remote command failed")
        else
            if reply.output and reply.output ~= "" then
                write(reply.output)
                if reply.output:sub(-1) ~= "\n" then print() end
            end
            cwd = reply.cwd or cwd
        end
    end
end
