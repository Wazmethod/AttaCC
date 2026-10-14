local ioRegistry = require("lib.io_registry")

local args = { ... }
local cmd = args[1]
if not cmd or cmd == "help" or cmd == "--help" then
    print("ioctl list")
    print("ioctl hardware")
    print("ioctl bind  - guided physical hardware binding")
    print("ioctl show <name>")
    print("ioctl read <name>")
    print("ioctl write <name> <value>")
    return
end
local profileStore = require("lib.profile_store")
local function hardware()
    local names = peripheral.getNames()
    table.sort(names)
    print("ATTACC PHYSICAL HARDWARE")
    for i,name in ipairs(names) do
        print(string.format("%2d) %s [%s]",i,name,tostring(peripheral.getType(name))))
    end
    return names
end

local function prompt(label, fallback)
    write(label .. " [" .. tostring(fallback or "") .. "]: ")
    local result = read()
    return result == "" and fallback or result
end

local function bind()
    local names = hardware()
    print("Create a logical I/O binding in /etc/io.lua")
    local name = prompt("Logical binding name",nil)
    if not name or not name:match("^[%a_][%w_%-]*$") then
        error("logical name must start with a letter and contain letters, digits, '_' or '-'")
    end
    print(" 1) Peripheral   2) Redstone")
    local kind = tonumber(prompt("Kind", "1")) == 2 and "redstone" or "peripheral"
    print(" 1) Input   2) Output")
    local direction = tonumber(prompt("Direction", "1")) == 2 and "output" or "input"
    local binding = {kind=kind,direction=direction}
    if kind == "peripheral" then
        if #names == 0 then error("no peripherals attached") end
        local selection = tonumber(prompt("Hardware number",nil))
        if not selection or not names[selection] then error("invalid hardware selection") end
        binding.peripheral = names[selection]
        local methods = peripheral.getMethods(binding.peripheral) or {}
        table.sort(methods)
        print("Methods: " .. table.concat(methods,", "))
        binding.method = prompt("Method to call",nil)
        local valid = false
        for _,method in ipairs(methods) do if method == binding.method then valid = true end end
        if not valid then error("method not available on selected peripheral") end
    else
        local sides = {"top","bottom","left","right","front","back"}
        print("Sides: " .. table.concat(sides,", "))
        binding.side = prompt("Redstone side","back")
        local valid = false
        for _,side in ipairs(sides) do if side == binding.side then valid = true end end
        if not valid then error("invalid redstone side") end
    end
    print("Binding: " .. textutils.serialize(binding))
    write("Save this binding to /etc/io.lua [y/N]: ")
    if read():lower() ~= "y" then print("Cancelled") return end
    local io = profileStore.readIO()
    io.io = io.io or {}
    io.io.bindings = io.io.bindings or {}
    io.io.bindings[name] = binding
    local ok,err = profileStore.saveLayers(profileStore.readApps(),io)
    if not ok then error(err) end
    print("Saved: " .. tostring(err))
    print("Reboot this application to reload logical bindings.")
end

if cmd == "hardware" then hardware(); return end
if cmd == "bind" then bind(); return end

local name = args[2]

local function parseValue(value)
    if value == nil then return nil end
    if value == "true" or value == "on" then return true end
    if value == "false" or value == "off" then return false end
    local number = tonumber(value)
    if number ~= nil then return number end
    return value
end

if cmd == "list" then
    local list = ioRegistry.list()
    if #list == 0 then
        print("No logical I/O bindings configured.")
        print("Run ioctl hardware and ioctl bind to configure /etc/io.lua -> io.bindings")
        return
    end
    for _, item in ipairs(list) do
        local b = item.binding
        local target = b.peripheral or b.type or b.side or "-"
        print(string.format("%-18s %-7s %-10s %s",
            item.name, item.direction, item.kind, tostring(target)))
    end
    return
end

if cmd == "show" and name then
    local b = ioRegistry.describe(name)
    if not b then error("Unknown binding: " .. tostring(name)) end
    print(textutils.serialize(b))
    return
end

if cmd == "read" and name then
    local value, err = ioRegistry.read(name)
    if err then error(err) end
    print(textutils.serialize(value))
    return
end

if cmd == "write" and name then
    local value = parseValue(args[3])
    if value == nil then error("Missing value") end
    write("Write " .. tostring(name) .. " = " .. tostring(value) .. "? [y/N] ")
    local answer = read():lower()
    if answer ~= "y" and answer ~= "yes" then
        print("Cancelled.")
        return
    end
    local ok, err = ioRegistry.write(name, value)
    if not ok then error(err) end
    print("OK")
    return
end

print("Usage:")
print("  ioctl list")
print("  ioctl show <binding>")
print("  ioctl read <binding>")
print("  ioctl write <binding> <value>")
