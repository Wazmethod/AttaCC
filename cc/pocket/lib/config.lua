local M = {}

M.machine = {
    role = "pocket",
    name = "infra-pocket",
    label = "INFRA POCKET",
    modules = { "steamplant.remote" },
    network = "infra-main",
    networkLabel = "MAIN INFRA",
    tags = { "infra", "portable" },
}

M.runtime = {
    preset = "portable-client",
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
            binary = "sshd.lua",
            depends = { "network" },
            description = "SSH-like administrative shell over the logical CC network",
        },
        client = {
            enabled = true,
            binary = "clientd.lua",
            depends = { "network" },
            description = "Portable infrastructure client",
        },
        display = {
            enabled = true,
            binary = "displayd.lua",
            depends = { "core" },
            description = "Pocket local display service",
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

M.pocket = {
    sourceModule = "steamplant",

    -- "master": consume the selected Master's aggregated Pocket stream.
    -- "direct": listen to module telemetry/events directly on the infra bus.
    transport = "master",

    -- Dashboard plugin. "steamplant" maps to the built-in legacy renderer.
    -- Additional dashboards can be provided as dashboards/<name>_text.lua and
    -- dashboards/<name>_graphics.lua without changing the Pocket runtime.
    dashboard = "steamplant",

    pages = {
        "status",
        "control",
        "motor",
        "events",
        "system",
    },
}

M.display = {
    preferred = "auto",
    graphicsMode = 1,
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
