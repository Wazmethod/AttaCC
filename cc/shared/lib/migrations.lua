local paths = require("lib.paths")

local M = {}
local SCHEMA_VERSION = 4

local function ensureDir(path)
    if path and path ~= "" and not fs.exists(path) then fs.makeDir(path) end
end

local function ensureParent(path)
    local parent = fs.getDir(path)
    if parent ~= "" then ensureDir(parent) end
end

local function moveIfMissing(oldPath, newPath)
    if not oldPath or not newPath then return false end
    if fs.exists(newPath) or not fs.exists(oldPath) then return false end
    ensureParent(newPath)
    fs.move(oldPath, newPath)
    return true
end

local function mergeDir(oldPath, newPath)
    if not fs.exists(oldPath) or not fs.isDir(oldPath) then return 0 end
    ensureDir(newPath)
    local moved = 0
    for _, name in ipairs(fs.list(oldPath)) do
        local oldChild = fs.combine(oldPath, name)
        local newChild = fs.combine(newPath, name)
        if fs.isDir(oldChild) then
            moved = moved + mergeDir(oldChild, newChild)
        elseif not fs.exists(newChild) then
            fs.move(oldChild, newChild)
            moved = moved + 1
        end
    end
    return moved
end

local function readJson(path)
    if not fs.exists(path) then return nil end
    local h = fs.open(path, "r")
    if not h then return nil end
    local raw = h.readAll()
    h.close()
    local ok, data = pcall(textutils.unserializeJSON, raw)
    if ok and type(data) == "table" then return data end
    return nil
end

local function writeJson(path, value)
    ensureParent(path)
    local raw = textutils.serializeJSON(value)
    local h = fs.open(path, "w")
    if not h then return false end
    h.write(raw)
    h.close()
    return true
end

local function migrateConfig()
    local moved = 0
    local candidates = {
        { "/etc/infra/machine.lua", paths.machine },
        { ".infra/config/machine.lua", paths.machine },
        { "machine.local.lua", paths.machine },
        { "/etc/infra/profile.lua", paths.profile },
        { ".infra/config/profile.lua", paths.profile },
        { "profile.local.lua", paths.profile },
        { "/etc/infra/preset", paths.preset },
        { ".infra/install-preset", paths.preset },
    }
    for _, pair in ipairs(candidates) do
        if moveIfMissing(pair[1], pair[2]) then moved = moved + 1 end
    end

    moved = moved + mergeDir("/etc/infra/services", paths.serviceConfig)
    moved = moved + mergeDir("/etc/infra/systemd", paths.localUnits)
    moved = moved + mergeDir("/etc/infra/modules", paths.localModules)
    return moved
end

local function migrateVendorLayout()
    local moved = 0
    moved = moved + mergeDir("/usr/lib/infra/systemd", paths.vendorUnits)
    moved = moved + mergeDir("/usr/lib/infra/modules", paths.vendorModules)
    return moved
end

local function migratePackageState()
    local moved = 0
    local candidates = {
        { "/var/lib/infra/packages.json", paths.packages },
        { ".infra/packages.json", paths.packages },
        { "/var/lib/infra/version.json", paths.version },
        { ".infra/version.json", paths.version },
    }
    for _, pair in ipairs(candidates) do
        if moveIfMissing(pair[1], pair[2]) then moved = moved + 1 end
    end
    return moved
end

local function migrateRuntimeState()
    local moved = 0

    local runtimeCandidates = {
        "/var/lib/infra/runtime",
        ".infra/runtime",
    }
    for _, dir in ipairs(runtimeCandidates) do
        if fs.exists(dir) and fs.isDir(dir) then
            if fs.exists(fs.combine(dir, "services.json")) then
                if moveIfMissing(fs.combine(dir, "services.json"), paths.serviceState) then moved = moved + 1 end
            end
            if fs.exists(fs.combine(dir, "service-live.json")) then
                if moveIfMissing(fs.combine(dir, "service-live.json"), paths.liveState) then moved = moved + 1 end
            end
            if fs.exists(fs.combine(dir, "display-publish.json")) then
                if moveIfMissing(fs.combine(dir, "display-publish.json"), fs.combine(paths.displayRuntime, "publish.json")) then moved = moved + 1 end
            end
            if fs.exists(fs.combine(dir, "display-selection.json")) then
                if moveIfMissing(fs.combine(dir, "display-selection.json"), fs.combine(paths.displayRuntime, "selection.json")) then moved = moved + 1 end
            end
            if fs.exists(fs.combine(dir, "hosts.json")) then
                if moveIfMissing(fs.combine(dir, "hosts.json"), fs.combine(paths.remoteShellState, "hosts.json")) then moved = moved + 1 end
            end
        end
    end

    return moved
end

local function migratePersistentState()
    local moved = 0
    moved = moved + mergeDir("/var/lib/infra/storage", paths.storage)
    moved = moved + mergeDir(".infra/storage", paths.storage)

    -- Application state becomes component-owned. Unknown legacy state is kept
    -- under /var/lib/legacy-state rather than discarded.
    moved = moved + mergeDir("/var/lib/infra/state", "/var/lib/legacy-state")
    moved = moved + mergeDir(".infra/state", "/var/lib/legacy-state")
    return moved
end

local function migrateLogs()
    local moved = 0

    for _, old in ipairs({
        "/var/log/infra/journal.log",
        ".infra/runtime/runtime.log",
    }) do
        if moveIfMissing(old, paths.journal) then moved = moved + 1 end
    end

    local legacyServices = "/var/log/infra/services"
    if fs.exists(legacyServices) and fs.isDir(legacyServices) then
        for _, file in ipairs(fs.list(legacyServices)) do
            if file:match("%.log$") then
                local service = file:gsub("%.log$", "")
                local target = paths.serviceLog(service)
                if moveIfMissing(fs.combine(legacyServices, file), target) then moved = moved + 1 end
            end
        end
    end

    return moved
end

local function schema()
    local data = readJson(paths.schema)
    return data and tonumber(data.version) or 0
end

function M.currentVersion()
    return SCHEMA_VERSION
end

function M.run(opts)
    opts = opts or {}
    paths.ensureBase()

    local before = schema()
    local moved = 0

    -- These are convergence adapters, not application-version hops. Every
    -- adapter probes known historical layouts and moves data directly to the
    -- current canonical layout, so an old machine can jump straight to latest.
    moved = moved + migrateConfig()
    moved = moved + migrateVendorLayout()
    moved = moved + migratePackageState()
    moved = moved + migrateRuntimeState()
    moved = moved + migratePersistentState()
    moved = moved + migrateLogs()

    writeJson(paths.schema, {
        version = SCHEMA_VERSION,
        previousVersion = before,
        migratedAt = os.epoch("utc"),
    })

    if opts.verbose then
        print("Filesystem schema: " .. tostring(before) .. " -> " .. tostring(SCHEMA_VERSION))
        print("Migrated items: " .. tostring(moved))
    end

    return true, {
        previous = before,
        current = SCHEMA_VERSION,
        moved = moved,
    }
end

return M
