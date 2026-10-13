local M = {}

M.machine = {
    role = "master",
    name = "infra-master",
    label = "INFRA MASTER",
    modules = { "network", "display" },
    apps = { "master" },
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
    moduleControl = 4251,
    moduleAck = 4252,
    moduleData = 4253,
    moduleEvents = 4254,
    storageRequest = 4255,
    storageResponse = 4256,
}

M.timing = {
    masterPushSeconds = 0.50,
    sourceStaleMs = 6000,
    masterTimeoutMs = 12000,
    commandRetryMs = 350,
    commandMaxRetries = 5,
}

M.events = {
    historySize = 50,
}

M.storage = {
    module = "network.storage",

    -- auto: use a data disk labelled ATTACC_STORAGE when available at startup,
    -- otherwise use the local computer filesystem.
    -- drive: require the labelled Drive media and degrade while it is absent.
    -- local: always use /var/lib/storage.
    backend = "auto",
    driveLabel = "ATTACC_STORAGE",
    driveName = nil,
    drivePath = "attacc/storage/store.json",

    file = "/var/lib/storage/store.json",
    maxValueBytes = 4096,
    maxKeys = 512,
}

M.master = {
    historySamples = 120,

    home = {
        machines = true,
        network = true,
        events = true,
        storage = true,
        web = true,
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

return M
