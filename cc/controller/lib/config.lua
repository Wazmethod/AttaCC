local M = {}

M.machine = {
    role = "controller",
    name = "infra-controller",
    label = "INFRA CONTROLLER",
    network = "infra-main",
    networkLabel = "MAIN INFRA",
    modules = { "core.controller" },
    tags = { "infra", "controller" },
}

M.runtime = {
    preset = "automation-node",
    services = {
        core = {
            enabled = true,
            protected = true,
            description = "Machine runtime and lifecycle",
        },
        network = {
            enabled = true,
            protected = true,
            depends = { "core" },
            description = "Logical network, discovery and message transport",
        },
        controller = {
            enabled = true,
            depends = { "network" },
            description = "Automation/state-machine execution and physical outputs",
        },
    },
}

M.io = {
    bindings = {},
}

M.channels = {
    telemetry = 4242,
    pocketStatus = 4243,
    control = 4245,
    ack = 4246,
    events = 4247,
    nodeControl = 4248,
    nodeAck = 4249,
    nodeStatus = 4250,
    moduleControl = 4251,
    moduleAck = 4252,
    moduleData = 4253,
    moduleEvents = 4254,
}

M.controller = {
    tick = 0.10,

    -- Lua module names loaded from modules/<name>.lua.
    -- Example for the future elevator machine:
    -- modules = { "elevator" }
    modules = {},
}


-- Optional logical relationships exported to the Web topology view.
-- Example:
-- links = {
--   { type = "controls", target = "infra:elevator-main", module = "elevator" },
-- }
M.topology = {
    links = {},
}


-- Per-instance runtime profile. This file is intentionally not managed by the
-- installer, so one collector/pocket/master/controller can have a different
-- module/display/peripheral setup from another machine with the same role.
local function merge(base, override)
    if type(override) ~= "table" then return base end
    for k, v in pairs(override) do
        if type(v) == "table" and type(base[k]) == "table" then
            merge(base[k], v)
        else
            base[k] = v
        end
    end
    return base
end

if fs.exists("profile.local.lua") then
    local ok, profile = pcall(dofile, "profile.local.lua")
    if ok and type(profile) == "table" then
        merge(M, profile)
    else
        error("Invalid profile.local.lua: " .. tostring(profile))
    end
end

return M
