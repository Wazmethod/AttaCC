local ok, err = pcall(function()
    shell.run("init.lua")
end)

if not ok then
    printError("init failed: " .. tostring(err))
end
