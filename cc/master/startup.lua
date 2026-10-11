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
        local displayId = launchService("displayd.lua", "display")
        print("Display module launched in tab " .. tostring(displayId))
    end

    if services.isActive("remote-shell") and fs.exists("sshd.lua") then
        local sshId = launchService("sshd.lua", "remote-shell")
        print("Remote shell service launched in tab " .. tostring(sshId))
    end

    local mainId = launchService("main.lua", "master")
    print("Master service launched in tab " .. tostring(mainId))

    if fs.exists("web.local.lua") then
        local webId = launchService("webbridge.lua", "webbridge")
        print("Web bridge launched in tab " .. tostring(webId))
    end

    print("Interactive shell ready. Use 'systemctl list' for service state.")
else
    local function runMaster() shell.run("main.lua") end
    local function runWebBridge() shell.run("webbridge.lua") end
    local function runRemote() shell.run("sshd.lua") end
    local function runDisplay() shell.run("displayd.lua") end
    local runners = { runMaster }
    if fs.exists("web.local.lua") then table.insert(runners, runWebBridge) end
    if services.isActive("remote-shell") and fs.exists("sshd.lua") then table.insert(runners, runRemote) end
    if fs.exists("displayd.lua") then table.insert(runners, runDisplay) end
    parallel.waitForAny(table.unpack(runners))
end
