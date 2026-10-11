local function launchService(path, title)
    if multishell then
        local id = multishell.launch({}, path)
        if title and multishell.setTitle then pcall(multishell.setTitle, id, title) end
        return id
    end
    shell.run(path)
    return nil
end

if multishell then
    local id = launchService("main.lua", "collector")
    print("Collector service launched in tab " .. tostring(id))
    print("Interactive shell ready. Use 'systemctl list' for service state.")
else
    shell.run("main.lua")
end
