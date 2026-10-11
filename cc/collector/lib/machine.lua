local config = require("lib.config")

local M = {}

local function copyTable(source)
    local out = {}
    if type(source) == "table" then
        for k, v in pairs(source) do out[k] = v end
    end
    return out
end

local function merge(base, override)
    local out = copyTable(base)
    if type(override) == "table" then
        for k, v in pairs(override) do
            if type(v) == "table" and type(out[k]) == "table" then
                out[k] = merge(out[k], v)
            else
                out[k] = v
            end
        end
    end
    return out
end

local function deriveRuntimeModules(role)
    local out = {}

    if role == "collector" and config.collector and type(config.collector.modules) == "table" then
        for _, name in ipairs(config.collector.modules) do table.insert(out, name) end
        if config.localDisplay and config.localDisplay.enabled then table.insert(out, "collector.display") end
        return out
    end

    if role == "controller" and config.controller and type(config.controller.modules) == "table" then
        for _, name in ipairs(config.controller.modules) do table.insert(out, name) end
        return out
    end

    if role == "pocket" and config.pocket then
        table.insert(out, "client.pocket")
        if config.pocket.sourceModule then table.insert(out, config.pocket.sourceModule) end
        return out
    end

    if role == "master" and config.master then
        table.insert(out, "client.master")
        if config.master.sourceModule then table.insert(out, config.master.sourceModule) end
        table.insert(out, "web.bridge")
        return out
    end

    return nil
end

function M.get(fallbackRole)
    local base = config.machine or {}
    local override = nil

    if fs.exists("machine.local.lua") then
        local ok, value = pcall(dofile, "machine.local.lua")
        if ok and type(value) == "table" then override = value end
    end

    local machine = merge(base, override)
    machine.identitySource = override and override.key and "local" or "physical-fallback"
    machine.persistentIdentity = machine.identitySource == "local"
    machine.role = machine.role or fallbackRole or "node"
    machine.computerId = os.getComputerID()
    machine.name = machine.name or (machine.role .. "-" .. tostring(machine.computerId))
    machine.label = machine.label or (string.upper(machine.role) .. " #" .. tostring(machine.computerId))
    local runtimeModules = deriveRuntimeModules(machine.role)
    machine.modules = runtimeModules or machine.modules or {}
    machine.tags = machine.tags or {}
    machine.network = machine.network or "default"
    machine.networkLabel = machine.networkLabel or string.upper(tostring(machine.network))

    -- Stable logical identity is independent from the physical CC computer ID.
    -- machine.local.lua may preserve this key across upgrades/replacements.
    machine.key = machine.key or ("cc:" .. tostring(machine.computerId))
    machine.logicalIdentity = machine.key
    machine.physicalIdentity = "cc:" .. tostring(machine.computerId)

    return machine
end

function M.hasModule(machine, moduleName)
    if type(machine) ~= "table" or type(machine.modules) ~= "table" then return false end
    for _, name in ipairs(machine.modules) do
        if name == moduleName then return true end
    end
    return false
end

return M
