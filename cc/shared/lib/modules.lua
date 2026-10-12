local services = require("lib.services")
local runtime = require("lib.runtime")

local M = {}
local MODULE_DIR = ".infra/modules"

local function normalizeService(name)
    return tostring(name or ""):gsub("%.service$", "")
end

local function definitions()
    local out = {}
    if not fs.exists(MODULE_DIR) or not fs.isDir(MODULE_DIR) then return out end

    for _, file in ipairs(fs.list(MODULE_DIR)) do
        if file:match("%.mod%.lua$") then
            local ok, def = pcall(dofile, fs.combine(MODULE_DIR, file))
            if ok and type(def) == "table" then
                local name = def.name or file:gsub("%.mod%.lua$", "")
                out[name] = def
            end
        end
    end
    return out
end

local function peripheralPresent(expected)
    if not expected then return true end
    if type(expected) == "string" then
        return peripheral.find(expected) ~= nil
    end
    if type(expected) == "table" then
        for _, kind in ipairs(expected) do
            if peripheral.find(kind) == nil then return false, kind end
        end
        return true
    end
    return true
end

function M.definition(name)
    return definitions()[name]
end

function M.names()
    local names = {}
    for name in pairs(definitions()) do table.insert(names, name) end
    table.sort(names)
    return names
end

function M.status(name)
    local def = definitions()[name]
    if not def then return nil end

    local missing = {}
    for _, requirement in ipairs(def.requires or {}) do
        local serviceName = normalizeService(requirement)
        local s = services.status(serviceName)
        if not s or not s.active then
            table.insert(missing, serviceName .. ".service")
        end
    end

    for _, path in ipairs(def.requiresFiles or {}) do
        if not fs.exists(path) then table.insert(missing, path) end
    end

    local peripheralOk, missingPeripheral = peripheralPresent(def.requiresPeripheral)
    if not peripheralOk then
        table.insert(missing, "peripheral:" .. tostring(missingPeripheral or def.requiresPeripheral))
    end

    local snap = runtime.snapshot()
    local observed = snap.services and snap.services["module:" .. name] or nil

    local state
    local detail
    if observed and observed.status == "failed" then
        state = "failed"
        detail = observed.detail or observed.error or "runtime failure"
    elseif #missing > 0 then
        state = "unavailable"
        detail = "missing " .. table.concat(missing, ", ")
    elseif observed and observed.status then
        state = observed.status
        detail = observed.detail or def.description
    else
        state = "loaded"
        detail = def.description or "module capability ready"
    end

    return {
        name = name,
        description = def.description,
        state = state,
        detail = detail,
        requires = def.requires or {},
        optional = def.optional == true,
        observed = observed,
        missing = missing,
    }
end

function M.syncRuntime()
    for _, name in ipairs(M.names()) do
        local s = M.status(name)
        local current = s.observed
        if not current or current.status ~= "failed" then
            runtime.set("module:" .. name, s.state, {
                detail = s.detail,
                requires = s.requires,
                optional = s.optional,
                installed = true,
            })
        end
    end
end

return M
