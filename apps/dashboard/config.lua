local M = {}

M.machine = {
    role = "dashboard",
    name = "attacc-dashboard",
    label = "ATTACC DASHBOARD",
    modules = { "network", "display", "dashboard" },
    apps = { "dashboard" },
    network = "infra-main",
    tags = { "display", "control" },
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

M.timing = {
    refreshSeconds = 0.5,
    sourceStaleMs = 6000,
    commandRetryMs = 350,
    commandMaxRetries = 5,
}

M.events = { historySize = 80 }

M.dashboard = {
    historySamples = 120,
    home = {
        machines = true,
        network = true,
        events = true,
        storage = false,
        web = false,
    },
}

M.display = {
    preferred = "auto",
    graphicsMode = 1,
    textScale = 0.5,
    forceTextScale = true,
}

local function merge(base, override)
    if type(override) ~= "table" then return base end
    for k,v in pairs(override) do
        if type(v)=="table" and type(base[k])=="table" then merge(base[k],v)
        else base[k]=v end
    end
    return base
end

if fs.exists("/etc/profile.lua") then
    local ok, profile = pcall(dofile, "/etc/profile.lua")
    if ok and type(profile)=="table" then merge(M,profile)
    else error("Invalid /etc/profile.lua: "..tostring(profile)) end
end

return M
