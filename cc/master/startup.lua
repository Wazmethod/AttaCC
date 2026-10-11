if fs.exists("startup/infra-completion.lua") then
    pcall(dofile, "startup/infra-completion.lua")
end

local services = require("lib.services")
local boot = require("lib.service_boot")

services.resetRuntimeOverrides()

if multishell then
    local ok, launched = boot.launchTabs()
    if not ok then
        printError(tostring(launched))
    else
        for _, item in ipairs(launched or {}) do
            print(string.format("%s.service -> %s [tab %s]",
                tostring(item.service), tostring(item.title), tostring(item.id)))
        end
    end
    print("Interactive shell ready. Use ps, systemctl and lsmod.")
else
    boot.runParallel()
end
