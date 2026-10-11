local machineInfo = require("lib.machine")

local args = { ... }
local cmd = args[1] or "status"

local function quote(s)
    return string.format("%q", tostring(s or ""))
end

local function hexEncode(s)
    return (s:gsub(".", function(c)
        return string.format("%02X", string.byte(c))
    end))
end

local function hexDecode(s)
    if type(s) ~= "string" or #s % 2 ~= 0 or s:find("[^0-9A-Fa-f]") then
        return nil, "invalid migration code"
    end
    return (s:gsub("..", function(cc)
        return string.char(tonumber(cc, 16))
    end))
end

local function loadLocal()
    if not fs.exists("machine.local.lua") then return {} end
    local ok, value = pcall(dofile, "machine.local.lua")
    if not ok or type(value) ~= "table" then
        return nil, "machine.local.lua is invalid"
    end
    return value
end

local function writeLocal(value)
    local lines = {
        "return {",
        "    key = " .. quote(value.key) .. ",",
        "    name = " .. quote(value.name) .. ",",
        "    label = " .. quote(value.label) .. ",",
    }

    if value.role then
        table.insert(lines, "    role = " .. quote(value.role) .. ",")
    end

    if type(value.modules) == "table" then
        table.insert(lines, "    modules = {")
        for _, moduleName in ipairs(value.modules) do
            table.insert(lines, "        " .. quote(moduleName) .. ",")
        end
        table.insert(lines, "    },")
    end

    if type(value.tags) == "table" then
        table.insert(lines, "    tags = {")
        for _, tag in ipairs(value.tags) do
            table.insert(lines, "        " .. quote(tag) .. ",")
        end
        table.insert(lines, "    },")
    end

    table.insert(lines, "}")

    local tmp = "machine.local.lua.new"
    local h = fs.open(tmp, "w")
    if not h then error("cannot write " .. tmp) end
    h.write(table.concat(lines, "\n") .. "\n")
    h.close()

    if fs.exists("machine.local.lua") then fs.delete("machine.local.lua") end
    fs.move(tmp, "machine.local.lua")
end

local function loadPackageVersion()
    local candidates = { ".infra/version.json", ".steamplant-version.json", "version.json" }

    for _, path in ipairs(candidates) do
        if fs.exists(path) then
            local h = fs.open(path, "r")
            if h then
                local raw = h.readAll()
                h.close()

                local ok, data = pcall(textutils.unserializeJSON, raw)
                if ok and type(data) == "table" then
                    return data
                end
            end
        end
    end

    return nil
end

local function printPackageVersion()
    local version = loadPackageVersion()

    if not version then
        print("Package     : unknown")
        return
    end

    local value = tostring(version.version or "unknown")
    if version.channel then
        value = value .. " (" .. tostring(version.channel) .. ")"
    end

    print("Package     : " .. value)

    if version.cc_package then
        print("CC package  : " .. tostring(version.cc_package))
    end
end

local function printMachine(machine)
    print("Machine key : " .. tostring(machine.key))
    print("Name        : " .. tostring(machine.name))
    print("Label       : " .. tostring(machine.label))
    print("Role        : " .. tostring(machine.role))
    print("Computer ID : " .. tostring(machine.computerId))
    print("Physical ID : " .. tostring(machine.physicalIdentity))
    print("Persistent  : " .. tostring(machine.persistentIdentity))
    printPackageVersion()
    print("Modules     : " .. table.concat(machine.modules or {}, ", "))
    print("Tags        : " .. table.concat(machine.tags or {}, ", "))
end

local function migrationPayload()
    local machine = machineInfo.get()
    local payload = {
        version = 1,
        key = machine.key,
        name = machine.name,
        label = machine.label,
        role = machine.role,
        modules = machine.modules,
        tags = machine.tags,
    }
    return textutils.serializeJSON(payload)
end

if cmd == "status" then
    printMachine(machineInfo.get())
    return
end

if cmd == "version" then
    printPackageVersion()
    return
end

if cmd == "init" then
    local current = machineInfo.get()
    local localCfg = loadLocal()
    if not localCfg then error("machine.local.lua is invalid") end

    write("Machine key [" .. tostring(current.key) .. "]: ")
    local key = read()
    if key == "" then key = current.key end

    write("Name [" .. tostring(current.name) .. "]: ")
    local name = read()
    if name == "" then name = current.name end

    write("Label [" .. tostring(current.label) .. "]: ")
    local label = read()
    if label == "" then label = current.label end

    localCfg.key = key
    localCfg.name = name
    localCfg.label = label
    writeLocal(localCfg)

    print("Saved.")
    printMachine(machineInfo.get())
    return
end

if cmd == "export" then
    local payload = migrationPayload()
    local code = "IM1-" .. hexEncode(payload)
    local exportFile = args[2] or "machine-migration.txt"

    local h = fs.open(exportFile, "w")
    if not h then error("Cannot write " .. tostring(exportFile)) end
    h.write(code .. "\n")
    h.close()

    print("Migration code exported.")
    print("File: " .. exportFile)
    print("")
    print("You can copy it with:")
    print("  edit " .. exportFile)
    print("")
    print("Turn this machine OFF before importing the code on its replacement.")
    return
end

if cmd == "import" then
    local code = args[2]
    if not code or code == "" then
        write("Migration code: ")
        code = read()
    end

    if code:sub(1,4) ~= "IM1-" then
        error("Unsupported migration code")
    end

    local raw, err = hexDecode(code:sub(5))
    if not raw then error(err) end

    local ok, payload = pcall(textutils.unserializeJSON, raw)
    if not ok or type(payload) ~= "table" or payload.version ~= 1 then
        error("Invalid migration payload")
    end
    if type(payload.key) ~= "string" or payload.key == "" then
        error("Migration payload has no machine key")
    end

    writeLocal({
        key = payload.key,
        name = payload.name,
        label = payload.label,
        role = payload.role,
        modules = payload.modules,
        tags = payload.tags,
    })

    print("Identity imported.")
    print("New physical Computer ID: " .. tostring(os.getComputerID()))
    print("Logical machine key kept: " .. tostring(payload.key))
    print("Reboot recommended.")
    return
end

if cmd == "reset" then
    if not fs.exists("machine.local.lua") then
        print("No local machine identity to reset.")
        return
    end

    write("Delete machine.local.lua? [y/N] ")
    local answer = read():lower()
    if answer == "y" or answer == "yes" then
        fs.delete("machine.local.lua")
        print("Local identity removed. Defaults will be used after reboot.")
    else
        print("Cancelled.")
    end
    return
end

print("Usage:")
print("  machinectl status")
print("  machinectl version")
print("  machinectl init")
print("  machinectl export [file]")
print("  machinectl import [migration-code]")
print("  machinectl reset")
