if fs.exists("startup/infra-completion.lua") then
    pcall(dofile, "startup/infra-completion.lua")
end

local services = require("lib.services")
services.resetRuntimeOverrides()

local function runClient() shell.run("main.lua") end
local function runRemote() shell.run("sshd.lua") end
local function runDisplay() shell.run("displayd.lua") end

local runners = { runClient }
if services.isActive("remote-shell") and fs.exists("sshd.lua") then table.insert(runners, runRemote) end
if fs.exists("displayd.lua") then table.insert(runners, runDisplay) end

if #runners > 1 then
    parallel.waitForAny(table.unpack(runners))
else
    runClient()
end
