if fs.exists("startup/infra-completion.lua") then
    pcall(dofile, "startup/infra-completion.lua")
end

local services = require("lib.services")
services.resetRuntimeOverrides()

local function launch(path, title)
    if shell.openTab then
        local id = shell.openTab(path)
        if title and multishell and multishell.setTitle then
            pcall(multishell.setTitle, id, title)
        end
        return id
    end
    return nil
end

if multishell then
    if fs.exists("displayd.lua") then
        local displayId = launchService and launchService("displayd.lua", "display")
            or launch and launch("displayd.lua", "display")
        if displayId then print("Display module launched in tab " .. tostring(displayId)) end
    end
    if services.isActive("remote-shell") and fs.exists("sshd.lua") then
        launch("sshd.lua", "remote-shell")
    end
    launch("main.lua", "workstation")
    print("Workstation online.")
    print("Interactive shell ready. Use 'ssh --scan' to discover hosts.")
else
    local function runNode() shell.run("main.lua") end
    local function runRemote() shell.run("sshd.lua") end
    local function runShell() shell.run("shell") end

    if services.isActive("remote-shell") and fs.exists("sshd.lua") then
        parallel.waitForAny(runNode, runRemote, runShell)
    else
        parallel.waitForAny(runNode, runShell)
    end
end
