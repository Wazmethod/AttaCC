local config = require("lib.config")
local serviceManager = require("lib.services")

local M = {}

local MACHINE_FILE = ".infra/config/machine.lua"
local LEGACY_MACHINE_FILE = "machine.local.lua"

local function migrateLocalConfig()
    if fs.exists(MACHINE_FILE) or not fs.exists(LEGACY_MACHINE_FILE) then return end
    local dir = fs.getDir(MACHINE_FILE)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    fs.move(LEGACY_MACHINE_FILE, MACHINE_FILE)
end

migrateLocalConfig()

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

local function canonicalModuleName(name)
    if name == "steamplant.collector" or name == "steam_plant" then return "steamplant" end
    return name
end

local function deriveRuntimeModules(role)
    local out = {}

    if role == "collector" and config.collector and type(config.collector.modules) == "table" then
        for _, name in ipairs(config.collector.modules) do
            table.insert(out, canonicalModuleName(name))
        end
        if config.localDisplay and config.localDisplay.enabled then table.insert(out, "collector.display") end
        return out
    end

    if role == "controller" and config.controller and type(config.controller.modules) == "table" then
        for _, name in ipairs(config.controller.modules) do
            table.insert(out, canonicalModuleName(name))
        end
        return out
    end

    if role == "pocket" and config.pocket then
        table.insert(out, "client.pocket")
        if config.pocket.sourceModule then table.insert(out, canonicalModuleName(config.pocket.sourceModule)) end
        return out
    end

    if role == "master" and config.master then
        table.insert(out, "client.master")
        if config.master.sourceModule then table.insert(out, canonicalModuleName(config.master.sourceModule)) end
        table.insert(out, "web.bridge")
        if config.storage and config.storage.module then
            table.insert(out, config.storage.module)
        end
        return out
    end

    return nil
end

function M.get(fallbackRole)
    local base = config.machine or {}
    local override = nil

    if fs.exists(MACHINE_FILE) then
        local ok, value = pcall(dofile, MACHINE_FILE)
        if ok and type(value) == "table" then override = value end
    end

    local machine = merge(base, override)
    machine.identitySource = override and override.key and "local" or "physical-fallback"
    machine.persistentIdentity = machine.identitySource == "local"
    -- "role" is retained only for migration/backward compatibility. New code
    -- should use preset + runtime services instead of treating role as identity.
    machine.role = machine.role or fallbackRole or "node"
    machine.preset = machine.preset
        or (config.runtime and config.runtime.preset)
        or machine.role
    machine.computerId = os.getComputerID()
    machine.hostname = machine.hostname or machine.name
        or (machine.preset .. "-" .. tostring(machine.computerId))
    -- name remains as a compatibility alias while UI/API callers migrate to hostname.
    machine.name = machine.hostname
    machine.label = machine.label or (string.upper(machine.preset) .. " #" .. tostring(machine.computerId))
    machine.services = serviceManager.capabilities()
    local runtimeModules = deriveRuntimeModules(machine.role)
    machine.modules = runtimeModules or machine.modules or {}

    local function hasModuleName(name)
        for _, moduleName in ipairs(machine.modules) do
            if moduleName == name then return true end
        end
        return false
    end

    local function displayMatchesProfile()
        if not fs.exists("displayd.lua") then return false end
        local section = config.standaloneDisplay
        if type(section) ~= "table" or section.enabled == false then return false end

        local configured = section.peripheral or section.monitor or section.monitorName
        if configured and configured ~= "" and configured ~= "auto" then
            if not peripheral.isPresent(configured) then return false end
            local types = { peripheral.getType(configured) }
            for _, t in ipairs(types) do if t == "monitor" then return true end end
            return false
        end
        return peripheral.find("monitor") ~= nil
    end

    if displayMatchesProfile() and not hasModuleName("core.display") then
        table.insert(machine.modules, "core.display")
    end

    if serviceManager.definition("remote-shell") then
        local found = false
        for _, moduleName in ipairs(machine.modules) do
            if moduleName == "core.remote-shell" then found = true break end
        end
        if not found then table.insert(machine.modules, "core.remote-shell") end
    end
    machine.tags = machine.tags or {}
    machine.network = machine.network or "default"
    machine.networkLabel = machine.networkLabel or string.upper(tostring(machine.network))
    machine.topology = config.topology or { links = {} }
    machine.topology.links = type(machine.topology.links) == "table" and machine.topology.links or {}

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
