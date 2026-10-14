-- Storage host maintenance utility. Installed only with module.storage-server.
local config = require("lib.config")
local profileStore = require("lib.profile_store")
local backendFactory = require("lib.storage_backend")
local argv = {...}
local cmd = argv[1]

local function usage()
    print("storagehostctl status")
    print("storagehostctl configure")
    print("storagehostctl backup [destination]")
    print("storagehostctl migrate <local|drive>")
    print("Migration copies and verifies data before changing the backend.")
end

local function loadProfile()
    if not fs.exists("/etc/profile.lua") then return {} end
    local ok, value = pcall(dofile, "/etc/profile.lua")
    return ok and type(value) == "table" and value or {}
end

local function ask(label, current)
    write(label .. " [" .. tostring(current or "") .. "]: ")
    local input = read()
    return input ~= "" and input or current
end

local function stats()
    return backendFactory.new(config):stats()
end

local function copyVerified(from, dest)
    if from == dest then return false, "source and destination are identical" end
    if not from or not fs.exists(from) then return false, "source store missing" end
    if fs.exists(dest) then return false, "destination already exists; refusing overwrite" end
    local dir = fs.getDir(dest)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local source = fs.open(from, "r")
    if not source then return false, "cannot open source" end
    local raw = source.readAll()
    source.close()
    local ok, parsed = pcall(textutils.unserializeJSON, raw)
    if not ok or type(parsed) ~= "table" or type(parsed.namespaces) ~= "table" then
        return false, "source is not a valid Storage database"
    end
    local tmp = dest .. ".migration"
    local h = fs.open(tmp, "w")
    if not h then return false, "cannot write destination" end
    h.write(raw)
    h.close()
    local verify = fs.open(tmp, "r")
    local copied = verify and verify.readAll() or nil
    if verify then verify.close() end
    if copied ~= raw then fs.delete(tmp) return false, "verification failed" end
    fs.move(tmp, dest)
    return true
end

if not cmd or cmd == "help" or cmd == "--help" then
    usage()
elseif cmd == "status" then
    print(textutils.serialize(stats()))
elseif cmd == "configure" then
    local profile = loadProfile()
    profile.storage = profile.storage or {}
    local current = config.storage or {}
    print("STORAGE HOST BACKEND")
    local backend = ask("Backend (auto/local/drive)", current.backend or "auto")
    if backend ~= "auto" and backend ~= "local" and backend ~= "drive" then error("invalid backend") end
    if backend ~= (current.backend or "auto") then
        print("Backend change: use storagehostctl migrate " .. backend .. " to preserve existing data.")
        return
    end
    profile.storage.backend = backend
    profile.storage.driveLabel = ask("Drive label",current.driveLabel or "ATTACC_STORAGE")
    profile.storage.driveName = ask("Drive peripheral (blank=automatic)",current.driveName or "")
    if profile.storage.driveName == "" then profile.storage.driveName = nil end
    profile.storage.drivePath = ask("Drive file",current.drivePath or "attacc/storage/store.json")
    profile.storage.file = ask("Local file",current.file or "/var/lib/storage/store.json")
    local ok, err = profileStore.saveProfile(profile)
    if not ok then error(err) end
    print("Saved. Reboot the host to apply.")
elseif cmd == "backup" then
    local state = stats()
    if not state.available or not state.file or not fs.exists(state.file) then error(state.error or "backend unavailable") end
    local dest = argv[2] or fs.combine("/var/lib/storage/backups", "store-" .. tostring(os.epoch("utc")) .. ".json")
    local ok, err = copyVerified(state.file, dest)
    if not ok then error(err) end
    print("Verified backup: "..dest)
elseif cmd == "migrate" then
    local target = argv[2]
    if target ~= "local" and target ~= "drive" then error("expected local or drive") end
    local state = stats()
    if not state.available or not state.file or not fs.exists(state.file) then error(state.error or "source unavailable") end
    if state.backend == target then print("Already using " .. target); return end
    local profile = loadProfile()
    profile.storage = profile.storage or {}
    local intended = {}
    for k,v in pairs(config.storage or {}) do intended[k]=v end
    intended.backend = target
    if target == "drive" then
        intended.driveLabel = ask("Target drive label",intended.driveLabel or "ATTACC_STORAGE")
        intended.drivePath = ask("Drive file",intended.drivePath or "attacc/storage/store.json")
    end
    local trial = {}
    for k,v in pairs(config) do trial[k]=v end
    trial.storage = intended
    local destination = backendFactory.new(trial):stats()
    if not destination.available or not destination.file then error(destination.error or "target unavailable") end
    print("FROM: "..state.file)
    print("TO  : "..destination.file)
    print("Pause all client writes before continuing.")
    write("Copy database and switch backend? type MIGRATE: ")
    if read() ~= "MIGRATE" then print("Cancelled") return end
    local ok, err = copyVerified(state.file, destination.file)
    if not ok then error(err) end
    profile.storage.backend = target
    profile.storage.driveLabel = intended.driveLabel
    profile.storage.drivePath = intended.drivePath
    profile.storage.driveName = intended.driveName
    local saved, saveErr = profileStore.saveProfile(profile)
    if not saved then error(saveErr) end
    print("Migration completed. Source remains intact: "..state.file)
    print("Reboot host before resuming writes.")
else
    usage()
    error("unknown host maintenance command")
end
