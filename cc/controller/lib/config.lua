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

return M
