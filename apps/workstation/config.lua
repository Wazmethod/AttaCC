local M = {}

M.machine = {
    role = "workstation",
    name = "infra-workstation",
    label = "INFRA WORKSTATION",
    network = "infra-main",
    modules = { "network", "display", "storage-client" },
    apps = { "workstation" },
    tags = { "infra", "workstation", "interactive" },
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

M.workstation = {
    console = {
        enabled = true,
        peripheral = "auto",
    },
}

M.standaloneDisplay = {
    enabled = true,
    peripheral = "auto",
    textScale = 0.5,
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
