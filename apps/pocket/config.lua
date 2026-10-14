local M = {}

M.machine = {
    role = "pocket",
    name = "infra-pocket",
    label = "INFRA POCKET",
    modules = { "network", "display" },
    apps = { "pocket" },
    network = "infra-main",
    tags = { "infra", "portable" },
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
}




M.timing = {
    appTickSeconds = 0.50,
    masterPushSeconds = 0.50,
    sourceStaleMs = 6000,
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

    -- Renderer family used by the Pocket. Navigation and controllable pages
    -- are generated dynamically from app descriptors received from the Master.
}

M.display = {
    preferred = "auto",
    graphicsMode = 1,
}




-- Per-instance runtime profile. This file is intentionally not managed by the
-- installer, so one AttaCC application can have a different
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

local PROFILE_FILE = "/etc/profile.lua"

if fs.exists(PROFILE_FILE) then
    local ok, profile = pcall(dofile, PROFILE_FILE)
    if ok and type(profile) == "table" then
        merge(M, profile)
    else
        error("Invalid " .. PROFILE_FILE .. ": " .. tostring(profile))
    end
end

-- Layered app/IO files override legacy profile for migrated installations.
require("lib.config_layers").load(M)

return M
