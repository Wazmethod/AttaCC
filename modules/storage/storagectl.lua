local storage = require("lib.storage_client")
local profileStore = require("lib.profile_store")
local config = require("lib.config")

local args = { ... }

local function usage()
    print("storagectl hosts")
    print("storagectl use <machine-key> [namespace]")
    print("storagectl target  - show selected host and namespace")
    print("storagectl ping")
    print("storagectl get <namespace> <key>")
    print("storagectl set <namespace> <key> <value|json>")
    print("storagectl delete <namespace> <key>")
    print("storagectl list <namespace>")
    print("storagectl ns")
    print("storagectl tree")
end

local command = args[1]
if not command then
    usage()
    return
end

local function loadProfile()
    if not fs.exists("/etc/profile.lua") then return {} end
    local ok, value = pcall(dofile, "/etc/profile.lua")
    return ok and type(value) == "table" and value or {}
end

local function prompt(label, current)
    write(label .. " [" .. tostring(current or "") .. "]: ")
    local value = read()
    return value == "" and current or value
end

local function show(value)
    if type(value) == "table" then
        print(textutils.serialize(value))
    elseif value == nil then
        print("nil")
    else
        print(tostring(value))
    end
end

if command == "ping" then
    local value, err = storage.ping()
    if err then error(err) end
    show(value)
elseif command == "get" then
    if not args[2] or not args[3] then error("namespace and key required") end
    local value, err = storage.get(args[2], args[3])
    if err then error(err) end
    show(value)
elseif command == "set" then
    if not args[2] or not args[3] or args[4] == nil then error("namespace, key and value required") end
    local raw = table.concat(args, " ", 4)
    local value = raw
    local ok, decoded = pcall(textutils.unserializeJSON, raw)
    if ok and decoded ~= nil then value = decoded end
    local result, err = storage.set(args[2], args[3], value)
    if err then error(err) end
    show(result)
elseif command == "delete" then
    if not args[2] or not args[3] then error("namespace and key required") end
    local result, err = storage.delete(args[2], args[3])
    if err then error(err) end
    show(result)
elseif command == "list" then
    if not args[2] then error("namespace required") end
    local result, err = storage.list(args[2])
    if err then error(err) end
    show(result)
elseif command == "ns" or command == "namespaces" then
    local result, err = storage.namespaces()
    if err then error(err) end
    if type(result) == "table" then
        for _, name in ipairs(result) do print(name) end
    else
        show(result)
    end
elseif command == "target" then
    local cfg = profileStore.storageConfig()
    print("Config sync: " .. (cfg.enabled and "enabled" or "disabled"))
    print("Host key   : " .. tostring(cfg.targetMachine or "(automatic)"))
    print("Namespace  : " .. tostring(cfg.namespace or "attacc.config"))
    print("Run storagectl hosts to discover servers.")
elseif command == "hosts" then
    local protocol = require("lib.protocol")
    local machine = require("lib.machine").get()
    local modem = protocol.findWirelessModem()
    if not modem then error("wireless modem unavailable") end
    local channel = config.channels.nodeStatus or 4250
    modem.open(channel)
    print("Discovering Storage hosts (5 seconds)...")
    local timer = os.startTimer(5)
    local results = {}
    while true do
        local event, _, ch, _, msg = os.pullEvent()
        if event == "timer" and _ == timer then break end
        if event == "modem_message" and ch == channel and type(msg) == "table"
            and msg.type == "node_status" and (not msg.network or msg.network == machine.network) then
            local state = msg.runtime and (msg.runtime["module:network.storage"] or msg.runtime["module:storage"])
            if state and (state.status == "active" or state.status == "degraded") then
                results[msg.key] = msg
            end
        end
    end
    local keys = {}
    for key in pairs(results) do keys[#keys+1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local node = results[key]
        print(tostring(key) .. " | " .. tostring(node.hostname or node.label or "?"))
    end
    if #keys == 0 then print("(no advertising Storage host detected)") end
elseif command == "use" then
    if not args[2] or args[2] == "" then error("storagectl use <machine-key> [namespace]") end
    local cfg = profileStore.storageConfig()
    cfg.enabled = true
    cfg.targetMachine = args[2]
    if args[3] and args[3] ~= "" then cfg.namespace = args[3] end
    local path = "/etc/storage.lua"
    local h = fs.open(path .. ".new", "w")
    if not h then error("cannot write " .. path) end
    h.write("return " .. textutils.serialize(cfg) .. "\\n")
    h.close()
    if fs.exists(path) then fs.delete(path) end
    fs.move(path .. ".new", path)
    print("Storage host selected: " .. tostring(cfg.targetMachine))
    print("Config namespace: " .. tostring(cfg.namespace))
    print("Use profilectl sync to pull this machine configuration.")
elseif command == "tree" or command == "browse" then
    local namespaces, err = storage.namespaces()
    if err then error(err) end

    if type(namespaces) ~= "table" or #namespaces == 0 then
        print("(no namespaces)")
        return
    end

    for _, namespace in ipairs(namespaces) do
        print(tostring(namespace) .. "/")
        local keysForNamespace, listErr = storage.list(namespace)
        if listErr then
            print("  ! " .. tostring(listErr))
        elseif type(keysForNamespace) ~= "table" or #keysForNamespace == 0 then
            print("  (empty)")
        else
            for _, key in ipairs(keysForNamespace) do
                print("  " .. tostring(key))
            end
        end
    end
else
    usage()
    error("unknown command")
end
