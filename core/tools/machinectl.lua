local machineInfo = require("lib.machine")
local profileStore = require("lib.profile_store")

local args = { ... }
local cmd = args[1] or "status"
local MACHINE_FILE = "/etc/machine.lua"

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
    if not fs.exists(MACHINE_FILE) then return {} end
    local ok, value = pcall(dofile, MACHINE_FILE)
    if not ok or type(value) ~= "table" then return nil, "machine config is invalid" end
    return value
end

local function writeLocal(value)
    local ok, detail = profileStore.saveMachine(value)
    if not ok then error(detail) end
    if detail and detail ~= "local" and detail ~= "synced" then
        print("Config: " .. tostring(detail))
    end
end

local function packageVersion()
    local path = "/var/lib/pkgctl/version.json"
    if not fs.exists(path) then return nil end
    local h = fs.open(path, "r")
    if not h then return nil end
    local raw = h.readAll()
    h.close()
    local ok, data = pcall(textutils.unserializeJSON, raw)
    return ok and type(data) == "table" and data or nil
end

local function printMachine(machine)
    print("Machine key : " .. tostring(machine.key))
    print("Hostname    : " .. tostring(machine.hostname or machine.name))
    print("Label       : " .. tostring(machine.label))
    print("Role        : " .. tostring(machine.role))
    print("Apps        : " .. table.concat(machine.apps or {}, ", "))
    print("Modules     : " .. table.concat(machine.modules or {}, ", "))
    print("Capabilities: " .. table.concat(machine.capabilities or {}, ", "))
    print("Network     : " .. tostring(machine.network))
    print("Network lbl : " .. tostring(machine.networkLabel))
    print("Computer ID : " .. tostring(machine.computerId))
    print("Physical ID : " .. tostring(machine.physicalIdentity))
    print("Persistent  : " .. tostring(machine.persistentIdentity))

    local version = packageVersion()
    if version then
        print("Version     : " .. tostring(version.version or "unknown")
            .. (version.channel and (" (" .. tostring(version.channel) .. ")") or ""))
    end
end

local function migrationPayload()
    local machine = machineInfo.get()
    return textutils.serializeJSON({
        version = 1,
        key = machine.key,
        hostname = machine.hostname or machine.name,
        label = machine.label,
        role = machine.role,
        network = machine.network,
        networkLabel = machine.networkLabel,
        tags = machine.tags,
    })
end

if cmd == "status" then
    printMachine(machineInfo.get())
    return
end

if cmd == "init" then
    local current = machineInfo.get()
    local cfg = loadLocal()
    if not cfg then error("machine config is invalid") end

    write("Machine key [" .. tostring(current.key) .. "]: ")
    local key = read(); if key == "" then key = current.key end
    write("Hostname [" .. tostring(current.hostname or current.name) .. "]: ")
    local hostname = read(); if hostname == "" then hostname = current.hostname or current.name end
    write("Label [" .. tostring(current.label) .. "]: ")
    local label = read(); if label == "" then label = current.label end
    write("Network [" .. tostring(current.network) .. "]: ")
    local network = read(); if network == "" then network = current.network end
    write("Network label [" .. tostring(current.networkLabel) .. "]: ")
    local networkLabel = read(); if networkLabel == "" then networkLabel = current.networkLabel end

    cfg.key, cfg.hostname, cfg.name = key, hostname, nil
    cfg.label, cfg.network, cfg.networkLabel = label, network, networkLabel
    writeLocal(cfg)
    print("Saved.")
    printMachine(machineInfo.get())
    return
end

if cmd == "hostname" then
    local current = machineInfo.get()
    if not args[2] or args[2] == "" then
        print(tostring(current.hostname or current.name))
        return
    end
    local cfg = loadLocal()
    if not cfg then error("machine config is invalid") end
    cfg.hostname, cfg.name = args[2], nil
    writeLocal(cfg)
    print("Hostname set to " .. tostring(args[2]) .. ".")
    print("Reboot recommended so running apps advertise it.")
    return
end

if cmd == "export" then
    local code = "IM1-" .. hexEncode(migrationPayload())
    local exportFile = args[2] or "machine-migration.txt"
    local h = fs.open(exportFile, "w")
    if not h then error("Cannot write " .. tostring(exportFile)) end
    h.write(code .. "\n")
    h.close()
    print("Migration code exported to " .. exportFile)
    return
end

if cmd == "import" then
    local code = args[2]
    if not code or code == "" then write("Migration code: "); code = read() end
    if code:sub(1,4) ~= "IM1-" then error("Unsupported migration code") end

    local raw, err = hexDecode(code:sub(5)); if not raw then error(err) end
    local ok, payload = pcall(textutils.unserializeJSON, raw)
    if not ok or type(payload) ~= "table" or payload.version ~= 1 then
        error("Invalid migration payload")
    end
    if type(payload.key) ~= "string" or payload.key == "" then
        error("Migration payload has no machine key")
    end

    writeLocal(payload)
    print("Identity imported for " .. tostring(payload.key) .. ".")
    print("Reboot recommended.")
    return
end

if cmd == "reset" then
    if not fs.exists(MACHINE_FILE) then print("No local machine identity to reset."); return end
    write("Delete local machine identity? [y/N] ")
    local answer = read():lower()
    if answer == "y" or answer == "yes" then
        fs.delete(MACHINE_FILE)
        print("Local identity removed. Defaults will be used after reboot.")
    else
        print("Cancelled.")
    end
    return
end

print("Usage:")
print("  machinectl status")
print("  machinectl init")
print("  machinectl hostname [new-hostname]")
print("  machinectl export [file]")
print("  machinectl import [migration-code]")
print("  machinectl reset")
