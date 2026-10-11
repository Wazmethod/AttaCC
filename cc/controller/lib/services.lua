local config = require("lib.config")
local runtime = require("lib.runtime")

local M = {}

local CONFIG_FILE = ".infra/runtime/service-config.json"
local LIVE_FILE = ".infra/runtime/service-live.json"

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

local function definitions()
    return (config.runtime and config.runtime.services) or {}
end

local function persisted()
    local data = readJson(CONFIG_FILE, { enabled = {} })
    data.enabled = type(data.enabled) == "table" and data.enabled or {}
    return data
end

local function liveState()
    local data = readJson(LIVE_FILE, { active = {} })
    data.active = type(data.active) == "table" and data.active or {}
    return data
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
    if requested == nil then requested = M.isEnabled(name) end
    if requested ~= true then return false end

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
    writeJson(LIVE_FILE, live)
    sleep(0)
    live = liveState()
    live.active[name] = true
    writeJson(LIVE_FILE, live)
    runtime.log("service:" .. name, "info", "service restart requested")
    return true
end

function M.status(name)
    local def = definitions()[name]
    if not def then return nil end
    local depsOk, missing = dependenciesSatisfied(name)
    return {
        name = name,
        description = def.description,
        depends = def.depends or {},
        enabled = M.isEnabled(name),
        active = M.isActive(name),
        protected = def.protected == true,
        dependenciesOk = depsOk,
        missingDependency = depsOk and nil or missing,
    }
end

function M.syncRuntime()
    for _, name in ipairs(M.names()) do
        local s = M.status(name)
        local status = s.active and "active" or (s.enabled and "inactive" or "disabled")
        runtime.set("service:" .. name, status, {
            detail = s.description,
            depends = s.depends,
            enabled = s.enabled,
            protected = s.protected,
            missingDependency = s.missingDependency,
        })
    end
end

return M
