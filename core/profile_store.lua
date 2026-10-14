local config = require("lib.config")
local M = {}

local PROFILE_FILE = "/etc/profile.lua"
local MACHINE_FILE = "/etc/machine.lua"
local STORAGE_FILE = "/etc/storage.lua"
local NAMESPACE = "attacc.config"
local REQUEST_CHANNEL = 4255
local RESPONSE_CHANNEL = 4256

local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k,v in pairs(value) do out[k] = copy(v) end
    return out
end

local function serialize(value, indent)
    indent = indent or ""
    local kind = type(value)
    if kind == "string" then return string.format("%q", value) end
    if kind == "number" or kind == "boolean" then return tostring(value) end
    if kind ~= "table" then return "nil" end

    local array, max = true, 0
    for k in pairs(value) do
        if type(k) ~= "number" then array = false break end
        if k > max then max = k end
    end

    local lines = { "{" }
    local child = indent .. "    "
    if array then
        for i=1,max do table.insert(lines, child .. serialize(value[i], child) .. ",") end
    else
        local keys = {}
        for k in pairs(value) do table.insert(keys, k) end
        table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
        for _,k in ipairs(keys) do
            local key = tostring(k):match("^[%a_][%w_]*$")
                and tostring(k) or ("[" .. string.format("%q", tostring(k)) .. "]")
            table.insert(lines, child .. key .. " = " .. serialize(value[k], child) .. ",")
        end
    end
    table.insert(lines, indent .. "}")
    return table.concat(lines, "\n")
end

local function readLua(path, fallback)
    if not fs.exists(path) then return copy(fallback) end
    local ok, value = pcall(dofile, path)
    if ok and type(value) == "table" then return value end
    return copy(fallback)
end

local function writeLua(path, value)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local tmp = path .. ".new"
    local h = fs.open(tmp, "w")
    if not h then return false, "cannot write " .. tmp end
    h.write("return " .. serialize(value) .. "\n")
    h.close()
    if fs.exists(path) then fs.delete(path) end
    fs.move(tmp, path)
    return true
end

local function storageConfig()
    local cfg = readLua(STORAGE_FILE, {
        enabled = false,
        targetMachine = nil,
        namespace = NAMESPACE,
        timeout = 2,
    })
    cfg.namespace = cfg.namespace or NAMESPACE
    cfg.timeout = tonumber(cfg.timeout) or 2
    return cfg
end

local function sanitizeMachine(value)
    value = type(value) == "table" and value or {}
    local out = {
        key = value.key,
        hostname = value.hostname or value.name,
        label = value.label,
        role = value.role,
        network = value.network,
    }
    if type(value.tags) == "table" then out.tags = copy(value.tags) end
    for k,v in pairs(out) do
        if v == nil then out[k] = nil end
    end
    return out
end

local function machineIdentity()
    local value = sanitizeMachine(readLua(MACHINE_FILE, {}))
    return {
        key = value.key or ("cc:" .. tostring(os.getComputerID())),
        network = value.network or "default",
    }
end

local function modem()
    local found = peripheral.find("modem", function(_, m)
        return m.isWireless and m.isWireless()
    end)
    return found
end

local seq = 0
local function request(action, key, value, timeout)
    local cfg = storageConfig()
    if not cfg.enabled then return nil, "storage sync disabled" end

    -- A machine which hosts Storage must never depend on modem loopback to
    -- configure or synchronize itself. Use the exact same backend locally.
    if fs.exists("lib/storage_backend.lua") then
        local backend = require("lib.storage_backend").new(config)
        local identity = machineIdentity()
        if action == "get" then return backend:get(cfg.namespace, key)
        elseif action == "set" then return backend:set(cfg.namespace, key, value, identity.key)
        elseif action == "delete" then return backend:delete(cfg.namespace, key)
        elseif action == "list" then return backend:list(cfg.namespace)
        elseif action == "namespaces" then return backend:namespaces()
        elseif action == "ping" then return backend:ping(), nil
        end
    end

    local m = modem()
    if not m then return nil, "wireless modem unavailable" end

    seq = seq + 1
    local id = "cfg-" .. tostring(os.getComputerID()) .. "-"
        .. tostring(os.epoch("utc")) .. "-" .. tostring(seq)
    local identity = machineIdentity()

    m.open(RESPONSE_CHANNEL)
    m.transmit(REQUEST_CHANNEL, REQUEST_CHANNEL, {
        type = "storage_request",
        id = id,
        action = action,
        namespace = cfg.namespace,
        key = key,
        value = value,
        origin = identity.key,
        network = identity.network,
        global = true,
        targetMachine = cfg.targetMachine,
        timestamp = os.epoch("utc"),
    })

    local timer = os.startTimer(timeout or cfg.timeout)
    while true do
        local event, p1, p2, _, p4 = os.pullEvent()
        if event == "timer" and p1 == timer then return nil, "storage sync timeout" end
        if event == "modem_message"
            and p2 == RESPONSE_CHANNEL
            and type(p4) == "table"
            and p4.type == "storage_response"
            and p4.id == id
        then
            if p4.ok then return p4.value, nil, p4 end
            return nil, p4.error or "storage request failed", p4
        end
    end
end

local function profileKey(machineKey) return "profile:" .. tostring(machineKey) end
local function machineKey(machineKey) return "machine:" .. tostring(machineKey) end

function M.storageConfig() return storageConfig() end
function M.enabled() return storageConfig().enabled == true end

function M.configure(value)
    value = value or {}
    local cfg = storageConfig()
    for k,v in pairs(value) do cfg[k] = v end
    return writeLua(STORAGE_FILE, cfg)
end

function M.getRemoteProfile(key)
    return request("get", profileKey(key))
end

function M.getRemoteMachine(key)
    return request("get", machineKey(key))
end

function M.pushProfile(key, profile)
    return request("set", profileKey(key), profile)
end

function M.pushMachine(key, machine)
    return request("set", machineKey(key), sanitizeMachine(machine))
end

function M.saveProfile(profile)
    local ok, err = writeLua(PROFILE_FILE, profile or {})
    if not ok then return false, err end

    if not M.enabled() then return true, "local" end
    local identity = machineIdentity()
    local _, pushErr = M.pushProfile(identity.key, profile or {})
    if pushErr then return true, "local; sync failed: " .. tostring(pushErr) end
    return true, "synced"
end

function M.saveMachine(machine)
    machine = sanitizeMachine(machine)
    local ok, err = writeLua(MACHINE_FILE, machine)
    if not ok then return false, err end

    if not M.enabled() then return true, "local" end
    local key = (machine and machine.key) or machineIdentity().key
    local _, pushErr = M.pushMachine(key, machine or {})
    if pushErr then return true, "local; sync failed: " .. tostring(pushErr) end
    return true, "synced"
end

function M.pushCurrent()
    if not M.enabled() then return false, "storage sync disabled" end
    local machine = readLua(MACHINE_FILE, {})
    local key = machine.key or machineIdentity().key
    local profile = readLua(PROFILE_FILE, {})

    local _, err = M.pushMachine(key, machine)
    if err then return false, err end
    local _, profileErr = M.pushProfile(key, profile)
    if profileErr then return false, profileErr end
    return true
end

function M.pullCurrent()
    if not M.enabled() then return false, "storage sync disabled" end

    local current = readLua(MACHINE_FILE, {})
    local key = current.key or machineIdentity().key

    local remoteMachine, machineErr = M.getRemoteMachine(key)
    if type(remoteMachine) == "table" then
        remoteMachine = sanitizeMachine(remoteMachine)
        remoteMachine.key = remoteMachine.key or key
        local ok, err = writeLua(MACHINE_FILE, remoteMachine)
        if not ok then return false, err end
    elseif machineErr and machineErr ~= "not found" then
        return false, machineErr
    else
        local _, pushErr = M.pushMachine(key, current)
        if pushErr then return false, pushErr end
    end

    local remoteProfile, profileErr = M.getRemoteProfile(key)
    if type(remoteProfile) == "table" then
        local ok, err = writeLua(PROFILE_FILE, remoteProfile)
        if not ok then return false, err end
    elseif profileErr and profileErr ~= "not found" then
        return false, profileErr
    else
        local localProfile = readLua(PROFILE_FILE, {})
        local _, pushErr = M.pushProfile(key, localProfile)
        if pushErr then return false, pushErr end
    end

    return true
end

function M.bootstrap()
    if not M.enabled() then return true, "local" end
    local ok, err = M.pullCurrent()
    if ok then return true, "synced" end
    return true, "local cache; " .. tostring(err)
end

function M.listMachines()
    local keys, err = request("list", nil)
    if not keys then return nil, err end
    local out = {}
    for _,key in ipairs(keys) do
        local machine = tostring(key):match("^machine:(.+)$")
        if machine then table.insert(out, machine) end
    end
    table.sort(out)
    return out
end

function M.editRemote(kind, key)
    if kind ~= "profile" and kind ~= "machine" then return false, "kind must be profile or machine" end
    if not key or key == "" then return false, "machine key required" end

    local value, err
    if kind == "profile" then value, err = M.getRemoteProfile(key)
    else value, err = M.getRemoteMachine(key) end
    if err and err ~= "not found" then return false, err end
    value = type(value) == "table" and value or {}

    local tmp = "/run/attacc/" .. kind .. "-" .. tostring(key):gsub("[^%w_.%-]", "_") .. ".lua"
    local ok, writeErr = writeLua(tmp, value)
    if not ok then return false, writeErr end

    shell.run("edit", tmp)
    local edited = readLua(tmp, nil)
    if type(edited) ~= "table" then return false, "edited file is invalid" end

    local result, pushErr
    if kind == "profile" then result, pushErr = M.pushProfile(key, edited)
    else
        edited.key = edited.key or key
        result, pushErr = M.pushMachine(key, edited)
    end
    if pushErr then return false, pushErr end
    return true
end

function M.handleCli(args)
    args = args or {}
    local cmd = args[1]
    if not cmd or cmd == "help" or cmd == "--help" then
        print("profilectl show           Full local machine configuration")
        print("profilectl status         Machine/profile overview")
        print("profilectl edit           Edit local profile")
        print("profilectl push           Upload local configuration")
        print("profilectl pull           Download stored configuration")
        print("profilectl machines       List machines in config storage")
        print("profilectl edit remote <machine-key> [profile|machine]")
        print("profilectl storage-sync   Configure synchronization")
        print("profilectl init           Initialize local profile")
        print("profilectl reset          Reset local profile")
        return true
    end

    if cmd == "pull" or cmd == "sync" then
        local ok, err = M.pullCurrent()
        print(ok and "Configuration synchronized from Storage." or ("Sync failed: " .. tostring(err)))
        return true
    end

    if cmd == "show" then
        local function view(path)
            if not fs.exists(path) then return {} end
            local ok, data = pcall(dofile, path)
            return ok and type(data) == "table" and data or {}
        end
        local identity = view(MACHINE_FILE)
        local profile = view(PROFILE_FILE)
        local cfg = view(STORAGE_FILE)
        print("ATTACC MACHINE CONFIGURATION")
        print("Effective application configuration (defaults + profile)")
        print(serialize(config))
        print("Machine identity (/etc/machine.lua)")
        print(serialize(identity))
        print("Runtime profile (/etc/profile.lua)")
        print(serialize(profile))
        print("Storage client (/etc/storage.lua)")
        print(serialize(cfg))
        return true
    end

    if cmd == "push" then
        local ok, err = M.pushCurrent()
        print(ok and "Local configuration pushed to Storage." or ("Push failed: " .. tostring(err)))
        return true
    end

    if cmd == "edit" and args[2] == "remote" then
        local ok, err = M.editRemote(args[4] or "profile", args[3])
        print(ok and "Remote configuration updated." or ("Remote edit failed: " .. tostring(err)))
        return true
    end

    if cmd == "remote" then
        local key = args[2]
        local kind = args[3] or "profile"
        local ok, err = M.editRemote(kind, key)
        print(ok and ("Remote " .. kind .. " updated for " .. tostring(key))
            or ("Remote edit failed: " .. tostring(err)))
        return true
    end

    if cmd == "machines" then
        local machines, err = M.listMachines()
        if not machines then print("Storage error: " .. tostring(err)); return true end
        for _,key in ipairs(machines) do print(key) end
        if #machines == 0 then print("(no synchronized machines)") end
        return true
    end

    if cmd == "storage-sync" then
        local cfg = storageConfig()
        write("Enable config sync [" .. (cfg.enabled and "Y/n" or "y/N") .. "]: ")
        local answer = read():lower()
        if answer ~= "" then cfg.enabled = answer=="y" or answer=="yes" end

        write("Storage host key [" .. tostring(cfg.targetMachine or "") .. "]: ")
        local target = read()
        if target ~= "" then cfg.targetMachine = target
        elseif cfg.targetMachine == "" then cfg.targetMachine = nil end

        write("Timeout seconds [" .. tostring(cfg.timeout or 2) .. "]: ")
        local timeout = read()
        if timeout ~= "" then cfg.timeout = tonumber(timeout) or cfg.timeout end

        local ok, err = writeLua(STORAGE_FILE, cfg)
        print(ok and ("Saved " .. STORAGE_FILE) or ("Error: " .. tostring(err)))
        return true
    end

    return false
end

return M
