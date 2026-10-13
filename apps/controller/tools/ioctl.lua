local ioRegistry = require("lib.io_registry")

local args = { ... }
local cmd = args[1] or "list"
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
        print("Edit profile.local.lua -> io.bindings")
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
