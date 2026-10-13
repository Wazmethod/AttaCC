local M = {}

M.machine = {
    role = "workstation",
    name = "infra-workstation",
    label = "INFRA WORKSTATION",
    network = "infra-main",
    networkLabel = "MAIN INFRA",
    modules = { "attacc.workstation", "core.console", "core.display" },
    tags = { "infra", "workstation", "interactive" },
}

M.runtime = {
    preset = "workstation",
    services = {
        network = {
            enabled = true,
            protected = true,
            description = "AttaCC network, discovery and message transport",
        },
        workstation = {
            enabled = true,
            binary = "workstationd.lua",
            description = "AttaCC interactive workstation application",
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

M.topology = {
    links = {},
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
