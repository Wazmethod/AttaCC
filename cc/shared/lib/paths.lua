local M = {
    machine = "/etc/machine.lua",
    profile = "/etc/profile.lua",
    preset = "/etc/preset",

    vendorUnits = "/usr/lib/systemd",
    localUnits = "/etc/systemd",
    serviceConfig = "/etc/services",
    serviceConfigState = "/etc/systemd/enabled.json",
    vendorModules = "/usr/lib/modules",
    localModules = "/etc/modules",

    pkgState = "/var/lib/pkgctl",
    packages = "/var/lib/pkgctl/packages.json",
    version = "/var/lib/pkgctl/version.json",

    systemState = "/var/lib/system",
    schema = "/var/lib/system/schema.json",

    runtime = "/run/systemd",
    serviceState = "/run/systemd/status.json",
    liveState = "/run/systemd/live.json",

    displayRuntime = "/run/display",
    remoteShellState = "/var/lib/remote-shell",
    storage = "/var/lib/storage",

    journal = "/var/log/journal.log",
}

local function ensureDir(path)
    if path and path ~= "" and not fs.exists(path) then fs.makeDir(path) end
end

function M.ensureBase()
    ensureDir("/etc")
    ensureDir(M.localUnits)
    ensureDir(M.serviceConfig)
    ensureDir(M.localModules)

    ensureDir("/usr")
    ensureDir("/usr/lib")
    ensureDir(M.vendorUnits)
    ensureDir(M.vendorModules)

    ensureDir("/var")
    ensureDir("/var/lib")
    ensureDir(M.pkgState)
    ensureDir(M.systemState)
    ensureDir(M.remoteShellState)
    ensureDir(M.storage)
    ensureDir("/var/log")

    ensureDir("/run")
    ensureDir(M.runtime)
    ensureDir(M.displayRuntime)
end

M.ensure = M.ensureBase

function M.serviceLogDir(service)
    local safe = tostring(service or "runtime")
        :gsub("^service:", "")
        :gsub("[^%w%._%-]", "_")
    return fs.combine("/var/log", safe)
end

function M.serviceLog(service)
    return fs.combine(M.serviceLogDir(service), "service.log")
end

function M.componentState(component)
    local safe = tostring(component or "runtime"):gsub("[^%w%._%-]", "_")
    return fs.combine("/var/lib", safe)
end

function M.ensureServiceLog(service)
    ensureDir(M.serviceLogDir(service))
end

-- Kept as a compatibility shim. Layout migration is implemented by
-- lib.migrations and may be invoked explicitly with the migrate command.
function M.migrate()
    M.ensureBase()
    local ok, migrations = pcall(require, "lib.migrations")
    if ok and migrations and migrations.run then
        return migrations.run()
    end
    return true
end

return M
