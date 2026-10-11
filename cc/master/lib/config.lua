local M = {}

M.machine = {
    role = "master",
    name = "infra-master",
    label = "INFRA MASTER",
    modules = { "steamplant.master", "web.bridge" },
    network = "infra-main",
    networkLabel = "MAIN INFRA",
    tags = { "infra", "control" },
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
}

M.redstone = {
    mainClutch = "top",
    alternatorClutch = "left",
    genClutch = "right",
}

M.procedure = {
    motorRPM = 64,
    minRPM = 32,
    stableMs = 2000,
    timeoutMs = 45000,
    transferDelayMs = 750,
    autoRestartDelayMs = 1500,
    verifyRunningMs = 8000,
    maxAutoAttempts = 3,
    retryDelayMs = 5000,
}

M.detection = {
    offlineRpm = 0.5,
    offlineCapacity = 1,
    onlineRpm = 16,
    onlineCapacity = 100,
    offlineConfirmMs = 5000,
    recoveryConfirmMs = 2000,
}

M.timing = {
    collectorTick = 0.50,
    masterPushSeconds = 0.50,
    collectorStaleMs = 6000,
    masterTimeoutMs = 12000,
    commandRetryMs = 350,
    commandMaxRetries = 5,
}

M.events = { historySize = 30 }

M.master = {
    sourceModule = "steamplant",
    pages = { "dashboard", "graphs", "events", "machines", "debug" },
}

M.display = {
    -- auto: prefer CC:Graphics when the monitor exposes the CraftOS-PC API,
    -- then fall back to the existing text renderer.
    -- text: force the classic CC:Tweaked renderer.
    preferred = "auto",
    graphicsMode = 1,
    textScale = 0.5,
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
