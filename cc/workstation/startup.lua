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
    if fs.exists("displayd.lua") then launch("displayd.lua", "core.display.mod") end
    if services.isActive("remote-shell") and fs.exists("sshd.lua") then
        launch("sshd.lua", "remote-shell.service")
    end
    launch("main.lua", "client.workstation.mod")
    print("Workstation online.")
    print("Interactive shell ready. Use 'ssh --scan' to discover hosts.")
else
    local function runNode() shell.run("main.lua") end
    local function runRemote() shell.run("sshd.lua") end
    local function runDisplay() shell.run("displayd.lua") end
    local function runShell() shell.run("shell") end
    local runners = { runNode, runShell }
    if services.isActive("remote-shell") and fs.exists("sshd.lua") then table.insert(runners, runRemote) end
    if fs.exists("displayd.lua") then table.insert(runners, runDisplay) end
    parallel.waitForAny(table.unpack(runners))
end
