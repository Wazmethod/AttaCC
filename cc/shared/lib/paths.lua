local M = {
    etc = "/etc",
    machine = "/etc/machine.lua",
    profile = "/etc/profile.lua",
    preset = "/etc/preset",

    vendorUnits = "/usr/lib/infra/systemd",
    localUnits = "/etc/systemd",
    serviceConfig = "/etc/services",
    vendorModules = "/usr/lib/infra/modules",
    localModules = "/etc/modules",

    var = "/var/lib/infra",
    runtime = "/var/lib/infra/runtime",
    state = "/var/lib/infra/state",
    packages = "/var/lib/infra/packages.json",
    storage = "/var/lib/infra/storage",

    log = "/var/log/infra",
    journal = "/var/log/infra/journal.log",
    serviceLogs = "/var/log/infra/services",
}

local function ensureDir(path)
    if path and path ~= "" and not fs.exists(path) then fs.makeDir(path) end
end

function M.ensure()
    ensureDir(M.etc)
    ensureDir(M.localUnits)
    ensureDir(M.serviceConfig)
    ensureDir(M.localModules)
    ensureDir(M.var)
    ensureDir(M.runtime)
    ensureDir(M.state)
    ensureDir(M.storage)
    ensureDir(M.log)
    ensureDir(M.serviceLogs)
end

local function moveIfMissing(oldPath, newPath)
    if fs.exists(newPath) or not fs.exists(oldPath) then return false end
    local parent = fs.getDir(newPath)
    if parent ~= "" then ensureDir(parent) end
    fs.move(oldPath, newPath)
    return true
end

local function mergeDir(oldPath, newPath)
    if not fs.exists(oldPath) or not fs.isDir(oldPath) then return false end
    ensureDir(newPath)
    for _, name in ipairs(fs.list(oldPath)) do
        local oldChild = fs.combine(oldPath, name)
        local newChild = fs.combine(newPath, name)
        if fs.isDir(oldChild) then
            mergeDir(oldChild, newChild)
        elseif not fs.exists(newChild) then
            fs.move(oldChild, newChild)
        end
    end
    return true
end

function M.migrate()
    M.ensure()

    moveIfMissing("/etc/infra/machine.lua", M.machine)
    moveIfMissing("/etc/infra/profile.lua", M.profile)
    moveIfMissing("/etc/infra/preset", M.preset)
    mergeDir("/etc/infra/services", M.serviceConfig)
    mergeDir("/etc/infra/systemd", M.localUnits)
    mergeDir("/etc/infra/modules", M.localModules)

    moveIfMissing(".infra/config/machine.lua", M.machine)
    moveIfMissing("machine.local.lua", M.machine)
    moveIfMissing(".infra/config/profile.lua", M.profile)
    moveIfMissing("profile.local.lua", M.profile)
    moveIfMissing(".infra/install-preset", M.preset)
    moveIfMissing(".infra/packages.json", M.packages)

    mergeDir(".infra/state", M.state)
    mergeDir(".infra/storage", M.storage)
    mergeDir(".infra/runtime", M.runtime)

    return true
end

return M
