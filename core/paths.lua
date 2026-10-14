local M = {
    machine = "/etc/machine.lua",
    profile = "/etc/profile.lua",
    preset = "/etc/preset",

    pkgState = "/var/lib/pkgctl",
    packages = "/var/lib/pkgctl/packages.json",
    version = "/var/lib/pkgctl/version.json",

    systemState = "/var/lib/attacc",
    schema = "/var/lib/attacc/schema.json",

    runtime = "/run/attacc",
    runtimeState = "/run/attacc/state.json",

    storage = "/var/lib/storage",
    journal = "/var/log/attacc/journal.log",
    logDir = "/var/log/attacc",
}

local function ensureDir(path)
    if path and path ~= "" and not fs.exists(path) then fs.makeDir(path) end
end

function M.ensureBase()
    ensureDir("/etc")
    ensureDir("/var")
    ensureDir("/var/lib")
    ensureDir(M.pkgState)
    ensureDir(M.systemState)
    ensureDir(M.storage)
    ensureDir("/var/log")
    ensureDir(M.logDir)
    ensureDir("/run")
    ensureDir(M.runtime)
end

M.ensure = M.ensureBase

function M.componentLogDir(component)
    local safe = tostring(component or "runtime")
        :gsub("^[^:]+:", "")
        :gsub("[^%w%._%-]", "_")
    return fs.combine(M.logDir, safe)
end

function M.componentLog(component)
    return fs.combine(M.componentLogDir(component), "runtime.log")
end

function M.ensureComponentLog(component)
    ensureDir(M.componentLogDir(component))
end

function M.componentState(component)
    local safe = tostring(component or "runtime"):gsub("[^%w%._%-]", "_")
    return fs.combine("/var/lib/attacc", safe)
end

return M
