local config = require("lib.config")

local M = {}
local MACHINE_FILE = "/etc/machine.lua"
local function copyTable(source)
    local out = {}
    if type(source) == "table" then
        for k, v in pairs(source) do
            if type(v) == "table" then
                out[k] = copyTable(v)
            else
                out[k] = v
            end
        end
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

local function uniqueSorted(values)
    local out, seen = {}, {}
    for _, value in ipairs(type(values) == "table" and values or {}) do
        value = tostring(value)
        if value ~= "" and not seen[value] then
            seen[value] = true
            table.insert(out, value)
        end
    end
    table.sort(out)
    return out
end


function M.get(fallbackRole)
    local base = config.machine or {}
    local override

    if fs.exists(MACHINE_FILE) then
        local ok, value = pcall(dofile, MACHINE_FILE)
        if ok and type(value) == "table" then override = value end
    end

    local machine = merge(base, override)
    machine.identitySource = override and override.key and "local" or "physical-fallback"
    machine.persistentIdentity = machine.identitySource == "local"
    machine.role = machine.role or fallbackRole or "node"
    machine.preset = machine.preset or machine.role
    machine.computerId = os.getComputerID()
    machine.hostname = machine.hostname or machine.name
        or (machine.preset .. "-" .. tostring(machine.computerId))
    machine.name = machine.hostname
    machine.label = machine.label
        or (string.upper(tostring(machine.preset)) .. " #" .. tostring(machine.computerId))
    machine.modules = uniqueSorted(machine.modules)
    machine.apps = uniqueSorted(machine.apps)
    machine.tags = uniqueSorted(machine.tags)
    machine.capabilities = uniqueSorted(machine.capabilities)
    machine.network = machine.network or "default"
    machine.networkLabel = machine.networkLabel or string.upper(tostring(machine.network))
    machine.topology = config.topology or machine.topology or { links = {} }
    machine.topology.links = type(machine.topology.links) == "table" and machine.topology.links or {}

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
