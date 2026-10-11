local storage = require("lib.storage_client")

local args = { ... }

local function usage()
    print("storagectl ping")
    print("storagectl get <namespace> <key>")
    print("storagectl set <namespace> <key> <value|json>")
    print("storagectl delete <namespace> <key>")
    print("storagectl list <namespace>")
end

local command = args[1]
if not command then
    usage()
    return
end

local function show(value)
    if type(value) == "table" then
        print(textutils.serialize(value))
    elseif value == nil then
        print("nil")
    else
        print(tostring(value))
    end
end

if command == "ping" then
    local value, err = storage.ping()
    if err then error(err) end
    show(value)
elseif command == "get" then
    if not args[2] or not args[3] then error("namespace and key required") end
    local value, err = storage.get(args[2], args[3])
    if err then error(err) end
    show(value)
elseif command == "set" then
    if not args[2] or not args[3] or args[4] == nil then error("namespace, key and value required") end
    local raw = table.concat(args, " ", 4)
    local value = raw
    local ok, decoded = pcall(textutils.unserializeJSON, raw)
    if ok and decoded ~= nil then value = decoded end
    local result, err = storage.set(args[2], args[3], value)
    if err then error(err) end
    show(result)
elseif command == "delete" then
    if not args[2] or not args[3] then error("namespace and key required") end
    local result, err = storage.delete(args[2], args[3])
    if err then error(err) end
    show(result)
elseif command == "list" then
    if not args[2] then error("namespace required") end
    local result, err = storage.list(args[2])
    if err then error(err) end
    show(result)
else
    usage()
    error("unknown command")
end
