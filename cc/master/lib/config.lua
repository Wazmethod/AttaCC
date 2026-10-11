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

M.runtime = {
    preset = "supervisor",
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
        ["remote-shell"] = {
            enabled = true,
            depends = { "network" },
            description = "SSH-like administrative shell over the logical CC network",
        },
        supervisor = {
            enabled = true,
            depends = { "network" },
            description = "Network supervision and wall dashboard aggregation",
        },
        display = {
            enabled = true,
            depends = { "core" },
            description = "Wall monitor/dashboard service",
        },
        webbridge = {
            enabled = true,
            depends = { "network", "supervisor" },
            description = "Bridge between CC infrastructure and hosted Web control plane",
        },
        storage = {
            enabled = true,
            depends = { "network" },
            description = "Persistent network shared key/value store",
        },
    },
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
    storageRequest = 4255,
    storageResponse = 4256,
    remoteShellRequest = 4257,
    remoteShellResponse = 4258,
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

M.storage = {
    module = "network.storage",
    file = ".infra/storage/store.json",
    maxValueBytes = 4096,
    maxKeys = 512,
}

M.master = {
    sourceModule = "steamplant",
    pages = { "dashboard", "graphs", "events", "machines", "topology", "debug" },
}

M.display = {
    -- auto: prefer CC:Graphics when the monitor exposes the CraftOS-PC API,
    -- then fall back to the existing text renderer.
    -- text: force the classic CC:Tweaked renderer.
    preferred = "auto",
    graphicsMode = 1,
    textScale = 0.5,
}


-- Optional logical relationships exported to the Web topology view.
-- Example:
-- links = {
--   { type = "controls", target = "infra:elevator-main", module = "elevator" },
-- }

M.remoteShell = {
    -- Optional pre-shared token. nil means logical-network access only.
    token = nil,
    sessionTtlMs = 300000,
    maxOutputBytes = 6000,
}

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

local PROFILE_FILE = ".infra/config/profile.lua"
local LEGACY_PROFILE_FILE = "profile.local.lua"

if not fs.exists(PROFILE_FILE) and fs.exists(LEGACY_PROFILE_FILE) then
    local dir = fs.getDir(PROFILE_FILE)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    fs.move(LEGACY_PROFILE_FILE, PROFILE_FILE)
end

if fs.exists(PROFILE_FILE) then
    local ok, profile = pcall(dofile, PROFILE_FILE)
    if ok and type(profile) == "table" then
        merge(M, profile)
    else
        error("Invalid " .. PROFILE_FILE .. ": " .. tostring(profile))
    end
end

return M
