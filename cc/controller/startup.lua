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
    local id = launchService("main.lua", "controller")
    print("Controller service launched in tab " .. tostring(id))
    print("Interactive shell ready. Use 'systemctl list' for service state.")
else
    shell.run("main.lua")
end
