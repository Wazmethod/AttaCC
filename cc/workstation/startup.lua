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
    if services.isActive("display") and fs.exists("displayd.lua") then launch("displayd.lua", "displayd") end
    if services.isActive("remote-shell") and fs.exists("sshd.lua") then
        launch("sshd.lua", "sshd")
    end
    launch("workstationd.lua", "workstationd")
    print("Workstation online.")
    print("Interactive shell ready. Use 'ssh --scan' to discover hosts.")
else
    local function runNode() shell.run("workstationd.lua") end
    local function runRemote() shell.run("sshd.lua") end
    local function runDisplay() shell.run("displayd.lua") end
    local function runShell() shell.run("shell") end
    local runners = { runNode, runShell }
    if services.isActive("remote-shell") and fs.exists("sshd.lua") then table.insert(runners, runRemote) end
    if services.isActive("display") and fs.exists("displayd.lua") then table.insert(runners, runDisplay) end
    parallel.waitForAny(table.unpack(runners))
end
