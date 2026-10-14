local storage = require("lib.storage_client")
local profileStore = require("lib.profile_store")
local config = require("lib.config")

local args = { ... }

local function usage()
    print("storagectl ping")
    print("storagectl get <namespace> <key>")
    print("storagectl set <namespace> <key> <value|json>")
    print("storagectl delete <namespace> <key>")
    print("storagectl list <namespace>")
    print("storagectl ns")
    print("storagectl tree")
    print("storagectl configure")
    print("storagectl check")
    print("storagectl backup [path]")
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
elseif command == "configure" then
    local profile = loadProfile()
    profile.storage = profile.storage or {}

    local current = config.storage or {}
    print("ATTACC STORAGE CONFIGURATION")
    print("----------------------------")
    profile.storage.backend = prompt("Backend (auto/local/drive)", current.backend or "auto")
    profile.storage.driveLabel = prompt("Drive media label", current.driveLabel or "ATTACC_STORAGE")

    local driveName = prompt("Pinned drive peripheral (blank = any)", current.driveName or "")
    profile.storage.driveName = driveName ~= "" and driveName or nil

    profile.storage.drivePath = prompt("Path on data disk", current.drivePath or "attacc/storage/store.json")
    profile.storage.file = prompt("Local backend file", current.file or "/var/lib/storage/store.json")
    profile.storage.maxValueBytes = tonumber(prompt("Max normal value bytes", current.maxValueBytes or 4096)) or 4096
    profile.storage.maxConfigBytes = tonumber(prompt("Max config value bytes", current.maxConfigBytes or 32768)) or 32768
    profile.storage.maxKeys = tonumber(prompt("Max keys", current.maxKeys or 512)) or 512

    local ok, detail = profileStore.saveProfile(profile)
    if not ok then error(detail) end
    print("Storage configuration saved.")
    if detail and detail ~= "local" and detail ~= "synced" then
        print("Config: " .. tostring(detail))
    end
    print("Reboot the storage host to apply backend selection.")
elseif command == "check" then
    local okBackend, backendFactory = pcall(require, "lib.storage_backend")
    if not okBackend then
        local value, err = storage.ping()
        if err then error(err) end
        show(value)
    else
        local backend = backendFactory.new(config)
        local stats = backend:stats()
        print("ATTACC STORAGE CHECK")
        print("--------------------")
        print("Backend    : " .. tostring(stats.backend or "?"))
        print("Available  : " .. tostring(stats.available == true))
        print("Drive      : " .. tostring(stats.drive or "-"))
        print("Disk ID    : " .. tostring(stats.diskId or "-"))
        print("File       : " .. tostring(stats.file or "-"))
        print("Namespaces : " .. tostring(stats.namespaces or 0))
        print("Keys       : " .. tostring(stats.keys or 0) .. " / " .. tostring(stats.maxKeys or "?"))
        if stats.file and fs.exists(stats.file) then
            print("Size       : " .. tostring(fs.getSize(stats.file)) .. " byte(s)")
        end
        if stats.error then print("Warning    : " .. tostring(stats.error)) end
    end
elseif command == "backup" then
    local okBackend, backendFactory = pcall(require, "lib.storage_backend")
    if not okBackend then error("backup requires module.storage-server on this machine") end
    local backend = backendFactory.new(config)
    local stats = backend:stats()
    if not stats.available or not stats.file or not fs.exists(stats.file) then
        error(stats.error or "storage backend unavailable")
    end

    local destination = args[2]
    if not destination or destination == "" then
        local dir = "/var/lib/storage/backups"
        if not fs.exists(dir) then fs.makeDir(dir) end
        destination = fs.combine(dir, "store-" .. tostring(os.epoch("utc")) .. ".json")
    end
    local dir = fs.getDir(destination)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    if fs.exists(destination) then fs.delete(destination) end
    fs.copy(stats.file, destination)
    print("Backup created: " .. tostring(destination))
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
