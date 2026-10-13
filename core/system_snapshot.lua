local runtime = require("lib.runtime")
local paths = require("lib.paths")

local M = {}
local cache
local cacheAt = 0

local function readJson(path)
    if not fs.exists(path) then return nil end
    local h = fs.open(path, "r")
    if not h then return nil end
    local raw = h.readAll()
    h.close()
    local ok, value = pcall(textutils.unserializeJSON, raw)
    if ok and type(value) == "table" then return value end
    return nil
end

local function packageList()
    local packageDb = readJson(paths.packages) or { installed = {} }
    local out = {}
    for name, meta in pairs(packageDb.installed or {}) do
        table.insert(out, {
            name = name,
            kind = meta.kind,
            version = meta.version,
            explicit = meta.explicit == true,
            configurable = meta.configurable == true,
            webConfigurable = meta.webConfigurable == true,
            installedAt = meta.installedAt,
        })
    end
    table.sort(out, function(a,b) return a.name < b.name end)
    return out
end

local function runtimeLists()
    local snap = runtime.snapshot()
    local entries = snap.entries or {}
    local apps, modules, capabilities = {}, {}, {}

    for name, entry in pairs(entries) do
        local bucket, short
        short = name:match("^app:(.+)$")
        if short then bucket = apps end
        if not bucket then
            short = name:match("^module:(.+)$")
            if short then bucket = modules end
        end
        if not bucket then
            short = name:match("^capability:(.+)$")
            if short then bucket = capabilities end
        end

        if bucket then
            table.insert(bucket, {
                name = short,
                state = entry.status or "unknown",
                detail = entry.detail,
                since = entry.since,
                updatedAt = entry.updatedAt,
                data = entry.webData,
            })
        end
    end

    local function sort(list)
        table.sort(list, function(a,b) return a.name < b.name end)
    end
    sort(apps); sort(modules); sort(capabilities)
    return entries, apps, modules, capabilities
end

local function processList()
    local out = {}
    if multishell then
        local current = multishell.getCurrent and multishell.getCurrent() or nil
        local focus = multishell.getFocus and multishell.getFocus() or nil
        for id = 1, multishell.getCount() do
            table.insert(out, {
                pid = id,
                name = multishell.getTitle(id) or ("tab-" .. tostring(id)),
                current = id == current,
                focused = id == focus,
            })
        end
    else
        table.insert(out, {
            pid = 1,
            name = shell.getRunningProgram() or "shell",
            current = true,
            focused = true,
        })
    end
    return out
end

function M.build(force)
    local now = os.epoch("utc")
    if not force and cache and (now - cacheAt) < 750 then return cache end

    local entries, apps, modules, capabilities = runtimeLists()

    cache = {
        generatedAt = now,
        uptimeMs = math.max(0, math.floor((os.clock() or 0) * 1000)),
        bootAt = now - math.max(0, math.floor((os.clock() or 0) * 1000)),
        logs = runtime.logs(80),
        schema = readJson(paths.schema),
        version = readJson(paths.version),
        apps = apps,
        modules = modules,
        capabilities = capabilities,
        runtime = entries,
        processes = processList(),
        packages = packageList()
    }
    cacheAt = now
    return cache
end

return M
