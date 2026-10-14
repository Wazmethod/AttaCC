local args = { ... }

local rebootOnSuccess = false
if args[1] == "--reboot-success" then
    rebootOnSuccess = true
    table.remove(args, 1)
end

local program = table.remove(args, 1)
if not program or program == "" then
    printError("runonce: program required")
    return
end

local ok = shell.run(program, table.unpack(args))

if ok == false then
    printError("runonce: command failed: " .. tostring(program))
    sleep(2)
    return
end

if rebootOnSuccess then
    print("Update complete. Rebooting...")
    sleep(0.5)
    os.reboot()
end
