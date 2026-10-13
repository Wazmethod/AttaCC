local paths = require("lib.paths")
paths.ensureBase()

local migrations = require("lib.migrations")
local migrationOk, migrationResult = migrations.run()
if not migrationOk then
    error("filesystem migration failed: " .. tostring(migrationResult))
end

local runtime = nil

local function bootSystem()
    if fs.exists("startup/infra-completion.lua") then
        pcall(dofile, "startup/infra-completion.lua")
    end

    local services = require("lib.services")
    local modules = require("lib.modules")
    local boot = require("lib.service_boot")
    runtime = require("lib.runtime")

    runtime.set("service:init", "starting", {
        detail = "loading service and module definitions",
        binary = "init.lua",
        process = false,
        embedded = true,
    })
    runtime.log("service:init", "info", "init start")

    services.resetRuntimeOverrides()
    services.syncRuntime()
    modules.syncRuntime()

    local ok, launched
    if multishell then
        ok, launched = boot.launchTabs()
    else
        ok = boot.runParallel()
        launched = {}
    end

    if not ok then error(tostring(launched)) end

    runtime.set("service:init", "active", {
        detail = "boot sequence completed",
        binary = "init.lua",
        process = false,
        embedded = true,
    })
    runtime.log("service:init", "info", "boot sequence completed")

    if multishell then
        for _, item in ipairs(launched or {}) do
            print(string.format("%s -> %s [tab %s]",
                table.concat(item.services or {}, ","),
                tostring(item.title),
                tostring(item.id)))
        end
        print("System ready. Use systemctl, lsmod and ps.")
    end
end

local ok, err = xpcall(bootSystem, function(value)
    if debug and debug.traceback then return debug.traceback(value, 2) end
    return tostring(value)
end)

if not ok then
    if runtime then
        runtime.set("service:init", "failed", {
            detail = tostring(err),
            binary = "init.lua",
            process = false,
            embedded = true,
            result = "exit-code",
        })
        runtime.log("service:init", "error", tostring(err))
    end
    printError("init failed: " .. tostring(err))
    return false
end

return true
