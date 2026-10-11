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
    if services.isActive("remote-shell") and fs.exists("sshd.lua") then
        local sshId = launchService("sshd.lua", "remote-shell")
        print("Remote shell service launched in tab " .. tostring(sshId))
    end

    local id = launchService("main.lua", "controller")
    print("Controller service launched in tab " .. tostring(id))
    print("Interactive shell ready. Use 'systemctl list' for service state.")
else
    local function runMain() shell.run("main.lua") end
    local function runRemote() shell.run("sshd.lua") end
    if services.isActive("remote-shell") and fs.exists("sshd.lua") then
        parallel.waitForAny(runMain, runRemote)
    else
        runMain()
    end
end
