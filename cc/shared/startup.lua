local ok, result = pcall(shell.run, "init.lua")
if not ok then
    printError("init failed: " .. tostring(result))
elseif result == false then
    printError("init.service failed. Run: systemctl status init")
end
