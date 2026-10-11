local services = require("lib.services")
services.resetRuntimeOverrides()

local function launchService(path, title)
    local id

    if shell.openTab then
        id = shell.openTab(path)
    elseif multishell then
        local env = setmetatable({}, { __index = _ENV })
        id = multishell.launch(env, path)
    end

    if id and title and multishell and multishell.setTitle then
        pcall(multishell.setTitle, id, title)
    end

    return id
end

if multishell then
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
    if fs.exists("web.local.lua") then
        parallel.waitForAny(runMaster, runWebBridge)
    else
        runMaster()
    end
end
