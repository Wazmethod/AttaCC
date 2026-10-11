if fs.exists("startup/infra-completion.lua") then
    pcall(dofile, "startup/infra-completion.lua")
end

local services = require("lib.services")
services.resetRuntimeOverrides()

-- Pocket computers keep their UI in the foreground, but the remote-shell
-- listener can run alongside it through the parallel scheduler.
local function runClient() shell.run("main.lua") end
local function runRemote() shell.run("sshd.lua") end

if services.isActive("remote-shell") and fs.exists("sshd.lua") then
    parallel.waitForAny(runClient, runRemote)
else
    runClient()
end
