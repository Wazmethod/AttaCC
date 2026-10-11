if fs.exists("startup/infra-completion.lua") then
    pcall(dofile, "startup/infra-completion.lua")
end

local services = require("lib.services")
services.resetRuntimeOverrides()

local function launchService(path, title)
    if shell.openTab then
        local id = shell.openTab(path)
        if title and multishell and multishell.setTitle then pcall(multishell.setTitle, id, title) end
        return id
    end

    if multishell then
        local env = setmetatable({}, { __index = _ENV })
        local id = multishell.launch(env, path)
        if title and multishell.setTitle then pcall(multishell.setTitle, id, title) end
        return id
    end

    return nil
end

if multishell then
    if fs.exists("displayd.lua") then
        local displayId = launchService("displayd.lua", "core.display.mod")
        print("Display module launched in tab " .. tostring(displayId))
    end

    if services.isActive("remote-shell") and fs.exists("sshd.lua") then
        local sshId = launchService("sshd.lua", "remote-shell.service")
        print("Remote shell service launched in tab " .. tostring(sshId))
    end

    local id = launchService("main.lua", "collector.service")
    print("Collector service launched in tab " .. tostring(id))
    print("Interactive shell ready. Use 'systemctl list' for service state.")
else
    local function runMain() shell.run("main.lua") end
    local function runRemote() shell.run("sshd.lua") end
    local function runDisplay() shell.run("displayd.lua") end
    local runners = { runMain }
    if services.isActive("remote-shell") and fs.exists("sshd.lua") then table.insert(runners, runRemote) end
    if fs.exists("displayd.lua") then table.insert(runners, runDisplay) end
    parallel.waitForAny(table.unpack(runners))
end
