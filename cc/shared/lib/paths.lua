local M = {
    etc = "/etc/infra",
    machine = "/etc/infra/machine.lua",
    profile = "/etc/infra/profile.lua",
    preset = "/etc/infra/preset",

    vendorUnits = "/usr/lib/infra/systemd",
    localUnits = "/etc/infra/systemd",
    vendorModules = "/usr/lib/infra/modules",
    localModules = "/etc/infra/modules",

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

function M.migrate()
    M.ensure()

    moveIfMissing(".infra/config/machine.lua", M.machine)
    moveIfMissing("machine.local.lua", M.machine)
    moveIfMissing(".infra/config/profile.lua", M.profile)
    moveIfMissing("profile.local.lua", M.profile)
    moveIfMissing(".infra/install-preset", M.preset)
    moveIfMissing(".infra/packages.json", M.packages)

    moveIfMissing(".infra/state", M.state)
    moveIfMissing(".infra/storage", M.storage)

    -- Runtime data is migrated only when the new runtime directory is empty.
    if fs.exists(".infra/runtime") and fs.isDir(".infra/runtime")
        and #fs.list(M.runtime) == 0
    then
        for _, name in ipairs(fs.list(".infra/runtime")) do
            local oldPath = fs.combine(".infra/runtime", name)
            local newPath = fs.combine(M.runtime, name)
            if not fs.exists(newPath) then fs.move(oldPath, newPath) end
        end
    end

    return true
end

return M
