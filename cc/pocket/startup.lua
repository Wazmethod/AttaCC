if multishell then
    local id = multishell.launch({}, "main.lua")
    if multishell.setTitle then pcall(multishell.setTitle, id, "pocket") end
    print("Pocket service launched in tab " .. tostring(id))
    print("Interactive shell ready. Use 'systemctl list' for service state.")
else
    shell.run("main.lua")
end
