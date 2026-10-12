local paths = require("lib.paths")
paths.migrate()

if fs.exists("startup/infra-completion.lua") then
    pcall(dofile, "startup/infra-completion.lua")
end

local services = require("lib.services")
local modules = require("lib.modules")
local boot = require("lib.service_boot")
local runtime = require("lib.runtime")

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

if not ok then
    runtime.log("service:init", "error", tostring(launched))
    printError(tostring(launched))
    return
end

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
