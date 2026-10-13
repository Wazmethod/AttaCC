local config = require("lib.config")
local runtime = require("lib.runtime")
local paths = require("lib.paths")

paths.ensure()

local M = {}

local CONFIG_FILE = paths.serviceConfigState
local LIVE_FILE = paths.liveState

local function ensureParent(path)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
end

local function readJson(path, fallback)
    if not fs.exists(path) then return fallback end
    local h = fs.open(path, "r")
    if not h then return fallback end
    local raw = h.readAll()
    h.close()
    local ok, value = pcall(textutils.unserializeJSON, raw)
    if ok and type(value) == "table" then return value end
    return fallback
end

local function writeJson(path, value)
    ensureParent(path)
    local ok, raw = pcall(textutils.serializeJSON, value)
    if not ok or not raw then return false end
    local tmp = path .. ".new"
    local h = fs.open(tmp, "w")
    if not h then return false end
    h.write(raw)
    h.close()
    if fs.exists(path) then fs.delete(path) end
    fs.move(tmp, path)
    return true
end

local function mergeInto(out, name, def)
    if type(def) ~= "table" then return end
    local merged = {}
    if type(out[name]) == "table" then
        for k, v in pairs(out[name]) do merged[k] = v end
    end
    for k, v in pairs(def) do merged[k] = v end
    out[name] = merged
end

local function loadUnitDir(out, dir)
    if not fs.exists(dir) or not fs.isDir(dir) then return end
    for _, file in ipairs(fs.list(dir)) do
        if file:match("%.service%.lua$") then
            local ok, def = pcall(dofile, fs.combine(dir, file))
            if ok and type(def) == "table" then
                local name = def.name or file:gsub("%.service%.lua$", "")
                def._unitPath = fs.combine(dir, file)
                mergeInto(out, name, def)
            end
        end
    end
end

local function loadServiceConfig(out)
    local dir = paths.serviceConfig
    if not fs.exists(dir) or not fs.isDir(dir) then return end

    for _, file in ipairs(fs.list(dir)) do
        if file:match("%.conf%.lua$") then
            local ok, def = pcall(dofile, fs.combine(dir, file))
            if ok and type(def) == "table" then
                local name = def.name or file:gsub("%.conf%.lua$", "")
                def.name = nil
                def._configPath = fs.combine(dir, file)
                mergeInto(out, name, def)
            end
        end
    end
end

local function definitions()
    local out = {}

    -- Legacy/preset runtime definitions are fallback defaults.
    for name, def in pairs((config.runtime and config.runtime.services) or {}) do
        mergeInto(out, name, def)
    end

    -- Package-owned vendor units are canonical and override legacy defaults.
    loadUnitDir(out, paths.vendorUnits)

    -- Local administrator unit overrides.
    loadUnitDir(out, paths.localUnits)

    -- Per-service configuration is the final override layer.
    loadServiceConfig(out)

    return out
end

local function persisted()
    local data = readJson(CONFIG_FILE, { enabled = {} })
    data.enabled = type(data.enabled) == "table" and data.enabled or {}
    return data
end

local function liveState()
    local data = readJson(LIVE_FILE, { active = {}, restartAt = {} })
    data.active = type(data.active) == "table" and data.active or {}
    data.restartAt = type(data.restartAt) == "table" and data.restartAt or {}
    return data
end

function M.resetRuntimeOverrides()
    return writeJson(LIVE_FILE, { active = {}, restartAt = {} })
end

function M.definition(name)
    return definitions()[name]
end

function M.names()
    local out = {}
    for name in pairs(definitions()) do table.insert(out, name) end
    table.sort(out)
    return out
end

function M.capabilities()
    local out = {}
    for _, name in ipairs(M.names()) do table.insert(out, name) end
    return out
end

function M.isEnabled(name)
    local def = definitions()[name]
    if not def then return false end
    local data = persisted()
    local value = data.enabled[name]
    if value == nil then return def.enabled ~= false end
    return value == true
end

local function dependenciesSatisfied(name, seen)
    local def = definitions()[name]
    if not def then return false, "unknown service" end
    seen = seen or {}
    if seen[name] then return false, "dependency cycle" end
    seen[name] = true

    for _, dep in ipairs(def.depends or {}) do
        if not M.isActive(dep, seen) then
            seen[name] = nil
            return false, dep
        end
    end

    seen[name] = nil
    return true
end

function M.isActive(name, seen)
    local live = liveState()
    local requested = live.active[name]
    local restartAt = tonumber(live.restartAt[name])
    if restartAt and os.epoch("utc") >= restartAt then
        requested = true
    end
    if requested == nil then requested = M.isEnabled(name) end
    if requested ~= true then return false end

    local def = definitions()[name]
    if def and def.requiresFile and not fs.exists(def.requiresFile) then return false end

    local ok = dependenciesSatisfied(name, seen)
    return ok == true
end

function M.enable(name)
    if not definitions()[name] then return false, "unknown service" end
    local data = persisted()
    data.enabled[name] = true
    writeJson(CONFIG_FILE, data)
    return true
end

function M.disable(name)
    local def = definitions()[name]
    if not def then return false, "unknown service" end
    if def.protected then return false, "protected service" end
    local data = persisted()
    data.enabled[name] = false
    writeJson(CONFIG_FILE, data)
    return true
end

local function startRecursive(name, stack)
    local def = definitions()[name]
    if not def then return false, "unknown service: " .. tostring(name) end
    stack = stack or {}
    if stack[name] then return false, "dependency cycle at " .. tostring(name) end
    stack[name] = true

    for _, dep in ipairs(def.depends or {}) do
        local ok, err = startRecursive(dep, stack)
        if not ok then return false, err end
    end

    local live = liveState()
    live.active[name] = true
    live.restartAt[name] = nil
    writeJson(LIVE_FILE, live)
    runtime.log("service:" .. name, "info", "service start requested")
    stack[name] = nil
    return true
end

function M.start(name)
    return startRecursive(name)
end

function M.stop(name)
    local def = definitions()[name]
    if not def then return false, "unknown service" end
    if def.protected then return false, "protected service" end

    for other, otherDef in pairs(definitions()) do
        if M.isActive(other) then
            for _, dep in ipairs(otherDef.depends or {}) do
                if dep == name then
                    return false, "required by active service: " .. tostring(other)
                end
            end
        end
    end

    local live = liveState()
    live.active[name] = false
    live.restartAt[name] = nil
    writeJson(LIVE_FILE, live)
    runtime.log("service:" .. name, "info", "service stop requested")
    return true
end

function M.restart(name)
    local def = definitions()[name]
    if not def then return false, "unknown service" end
    if def.protected then
        runtime.log("service:" .. name, "info", "protected service restart requested; reboot required")
        return false, "protected service; reboot the machine"
    end
    local live = liveState()
    live.active[name] = false
    live.restartAt[name] = os.epoch("utc") + 500
    writeJson(LIVE_FILE, live)
    runtime.log("service:" .. name, "info", "service soft-restart requested")
    return true
end

function M.status(name)
    local def = definitions()[name]
    if not def then return nil end
    local depsOk, missing = dependenciesSatisfied(name)
    local conditionOk = not def.requiresFile or fs.exists(def.requiresFile)
    return {
        name = name,
        description = def.description,
        binary = def.binary,
        modules = def.modules or {},
        web = def.web,
        unitPath = def._unitPath,
        configPath = def._configPath,
        requiresFile = def.requiresFile,
        depends = def.depends or {},
        enabled = M.isEnabled(name),
        active = M.isActive(name) and conditionOk,
        protected = def.protected == true,
        dependenciesOk = depsOk,
        missingDependency = depsOk and nil or missing,
        conditionOk = conditionOk,
        missingCondition = conditionOk and nil or def.requiresFile,
    }
end

function M.syncRuntime()
    local snapshot = runtime.snapshot()
    local liveStates = snapshot.services or {}
    local now = os.epoch("utc")

    for _, name in ipairs(M.names()) do
        local s = M.status(name)
        local key = "service:" .. name
        local live = liveStates[key]

        if not s.active then
            runtime.set(key, s.enabled and "inactive" or "disabled", {
                detail = s.description,
                binary = s.binary,
                process = false,
                depends = s.depends,
                enabled = s.enabled,
                protected = s.protected,
                missingDependency = s.missingDependency,
                missingCondition = s.missingCondition,
            })
        elseif live and live.status == "failed" then
            -- Preserve explicit runtime failures (including init/embedded services).
        elseif not s.binary then
            runtime.set(key, "active", {
                detail = s.description,
                process = false,
                embedded = true,
                depends = s.depends,
                enabled = s.enabled,
                protected = s.protected,
            })
        elseif not fs.exists(s.binary) then
            runtime.set(key, "failed", {
                detail = "binary missing: " .. tostring(s.binary),
                binary = s.binary,
                process = true,
                enabled = s.enabled,
            })
        else
            local processState = live and live.process == true and live.binary == s.binary
            local age = processState and live.updatedAt and (now - live.updatedAt) or nil

            if processState and (live.status == "failed" or live.status == "exited"
                or live.status == "stopping" or live.status == "inactive")
            then
                -- Keep the last process result until servicerun starts it again.
            elseif processState and age and age <= 3000 then
                -- servicerun owns the fresh runtime health entry.
            elseif processState and age and age > 3000 then
                runtime.set(key, "failed", {
                    detail = "process heartbeat stale",
                    binary = s.binary,
                    process = true,
                    enabled = s.enabled,
                })
            else
                runtime.set(key, "starting", {
                    detail = "waiting for process: " .. tostring(s.binary),
                    binary = s.binary,
                    process = true,
                    enabled = s.enabled,
                    depends = s.depends,
                })
            end
        end
    end
end
return M
