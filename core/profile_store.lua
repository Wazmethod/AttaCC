local config = require("lib.config")
local M = {}
local configHelp = require("lib.config_help")

local PROFILE_FILE = "/etc/profile.lua"
local MACHINE_FILE = "/etc/machine.lua"
local STORAGE_FILE = "/etc/storage.lua"
local NAMESPACE = "attacc.config"
local REQUEST_CHANNEL = 4255
local RESPONSE_CHANNEL = 4256

local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k,v in pairs(value) do out[k] = copy(v) end
    return out
end

local function serialize(value, indent)
    indent = indent or ""
    local kind = type(value)
    if kind == "string" then return string.format("%q", value) end
    if kind == "number" or kind == "boolean" then return tostring(value) end
    if kind ~= "table" then return "nil" end

    local array, max = true, 0
    for k in pairs(value) do
        if type(k) ~= "number" then array = false break end
        if k > max then max = k end
    end

    local lines = { "{" }
    local child = indent .. "    "
    if array then
        for i=1,max do table.insert(lines, child .. serialize(value[i], child) .. ",") end
    else
        local keys = {}
        for k in pairs(value) do table.insert(keys, k) end
        table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
        for _,k in ipairs(keys) do
            local key = tostring(k):match("^[%a_][%w_]*$")
                and tostring(k) or ("[" .. string.format("%q", tostring(k)) .. "]")
            table.insert(lines, child .. key .. " = " .. serialize(value[k], child) .. ",")
        end
    end
    table.insert(lines, indent .. "}")
    return table.concat(lines, "\n")
end

local function readLua(path, fallback)
    if not fs.exists(path) then return copy(fallback) end
    local ok, value = pcall(dofile, path)
    if ok and type(value) == "table" then return value end
    return copy(fallback)
end

local function writeLua(path, value)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local tmp = path .. ".new"
    local h = fs.open(tmp, "w")
    if not h then return false, "cannot write " .. tmp end
    h.write("return " .. serialize(value) .. "\n")
    h.close()
    if fs.exists(path) then fs.delete(path) end
    fs.move(tmp, path)
    return true
end

local function storageConfig()
    local cfg = readLua(STORAGE_FILE, {
        enabled = false,
        targetMachine = nil,
        namespace = NAMESPACE,
        timeout = 2,
    })
    cfg.namespace = cfg.namespace or NAMESPACE
    cfg.timeout = tonumber(cfg.timeout) or 2
    return cfg
end

local function sanitizeMachine(value)
    value = type(value) == "table" and value or {}
    local out = {
        key = value.key,
        hostname = value.hostname or value.name,
        label = value.label,
        role = value.role,
        network = value.network,
    }
    if type(value.tags) == "table" then out.tags = copy(value.tags) end
    for k,v in pairs(out) do
        if v == nil then out[k] = nil end
    end
    return out
end

local function machineIdentity()
    local value = sanitizeMachine(readLua(MACHINE_FILE, {}))
    return {
        key = value.key or ("cc:" .. tostring(os.getComputerID())),
        network = value.network or "default",
    }
end

local function modem()
    local found = peripheral.find("modem", function(_, m)
        return m.isWireless and m.isWireless()
    end)
    return found
end

local seq = 0
local function request(action, key, value, timeout)
    local cfg = storageConfig()
    if not cfg.enabled then return nil, "storage sync disabled (run profilectl storage-sync)" end
    if not cfg.targetMachine or cfg.targetMachine == "" then
        return nil, "Storage host not configured (run storagectl use <machine-key> [namespace])"
    end

    -- A machine which hosts Storage must never depend on modem loopback to
    -- configure or synchronize itself. Use the exact same backend locally.
    if cfg.targetMachine == machineIdentity().key and fs.exists("lib/storage_backend.lua") then
        local backend = require("lib.storage_backend").new(config)
        local identity = machineIdentity()
        if action == "get" then return backend:get(cfg.namespace, key)
        elseif action == "set" then return backend:set(cfg.namespace, key, value, identity.key)
        elseif action == "delete" then return backend:delete(cfg.namespace, key)
        elseif action == "list" then return backend:list(cfg.namespace)
        elseif action == "namespaces" then return backend:namespaces()
        elseif action == "ping" then return backend:ping(), nil
        end
    end

    local m = modem()
    if not m then return nil, "wireless modem unavailable" end

    seq = seq + 1
    local id = "cfg-" .. tostring(os.getComputerID()) .. "-"
        .. tostring(os.epoch("utc")) .. "-" .. tostring(seq)
    local identity = machineIdentity()

    m.open(RESPONSE_CHANNEL)
    m.transmit(REQUEST_CHANNEL, REQUEST_CHANNEL, {
        type = "storage_request",
        id = id,
        action = action,
        namespace = cfg.namespace,
        key = key,
        value = value,
        origin = identity.key,
        network = identity.network,
        global = true,
        targetMachine = cfg.targetMachine,
        timestamp = os.epoch("utc"),
    })

    local timer = os.startTimer(timeout or cfg.timeout)
    while true do
        local event, p1, p2, _, p4 = os.pullEvent()
        if event == "timer" and p1 == timer then
            return nil, "storage sync timeout (host=" .. tostring(cfg.targetMachine or "any")
                .. ", namespace=" .. tostring(cfg.namespace)
                .. ", network=" .. tostring(identity.network) .. ")"
        end
        if event == "modem_message"
            and p2 == RESPONSE_CHANNEL
            and type(p4) == "table"
            and p4.type == "storage_response"
            and p4.id == id
        then
            if p4.ok then return p4.value, nil, p4 end
            return nil, p4.error or "storage request failed", p4
        end
    end
end

local function profileKey(machineKey) return "profile:" .. tostring(machineKey) end
local function machineKey(machineKey) return "machine:" .. tostring(machineKey) end

function M.storageConfig() return storageConfig() end
function M.enabled() return storageConfig().enabled == true end

function M.configure(value)
    value = value or {}
    local cfg = storageConfig()
    for k,v in pairs(value) do cfg[k] = v end
    return writeLua(STORAGE_FILE, cfg)
end

function M.getRemoteProfile(key)
    return request("get", profileKey(key))
end

function M.getRemoteMachine(key)
    return request("get", machineKey(key))
end

function M.pushProfile(key, profile)
    return request("set", profileKey(key), profile)
end

function M.pushMachine(key, machine)
    return request("set", machineKey(key), sanitizeMachine(machine))
end

local APPS_FILE = "/etc/apps.lua"
local IO_FILE = "/etc/io.lua"

local function splitApplicationConfiguration(profile)
    local apps = copy(profile)
    local io = apps.io
    apps.io = nil
    return apps, io
end

function M.readApps() return readLua(APPS_FILE, {}) end
function M.readIO() return readLua(IO_FILE, {}) end

function M.saveLayers(apps, io)
    local ok, err = writeLua(APPS_FILE, apps or {})
    if not ok then return false, err end
    local ioOk, ioErr = writeLua(IO_FILE, io or {})
    if not ioOk then return false, ioErr end
    if M.enabled() then
        local pushed, pushErr = M.pushProfile(machineIdentity().key, {
            format = "attacc.config.v2",
            apps = apps or {}, io = io or {},
            legacy = readLua(PROFILE_FILE, {}),
        })
        if pushErr then return true, "local; sync failed: " .. tostring(pushErr) end
    end
    return true, "saved to apps.lua and io.lua"
end

function M.saveProfile(profile)
    local ok, err = writeLua(PROFILE_FILE, profile or {})
    if not ok then return false, err end

    if not M.enabled() then return true, "local" end
    local identity = machineIdentity()
    local _, pushErr = M.pushProfile(identity.key, {
        format = "attacc.config.v2", apps = M.readApps(), io = M.readIO(), legacy = profile or {},
    })
    if pushErr then return true, "local; sync failed: " .. tostring(pushErr) end
    return true, "synced"
end

function M.saveMachine(machine)
    machine = sanitizeMachine(machine)
    local ok, err = writeLua(MACHINE_FILE, machine)
    if not ok then return false, err end

    if not M.enabled() then return true, "local" end
    local key = (machine and machine.key) or machineIdentity().key
    local _, pushErr = M.pushMachine(key, machine or {})
    if pushErr then return true, "local; sync failed: " .. tostring(pushErr) end
    return true, "synced"
end

function M.pushCurrent()
    if not M.enabled() then return false, "storage sync disabled" end
    local machine = readLua(MACHINE_FILE, {})
    local key = machine.key or machineIdentity().key
    local profile = {
        format = "attacc.config.v2",
        apps = M.readApps(),
        io = M.readIO(),
        legacy = readLua(PROFILE_FILE, {}),
    }

    local _, err = M.pushMachine(key, machine)
    if err then return false, err end
    local _, profileErr = M.pushProfile(key, profile)
    if profileErr then return false, profileErr end
    return true
end

function M.pullCurrent()
    if not M.enabled() then return false, "storage sync disabled" end

    local current = readLua(MACHINE_FILE, {})
    local key = current.key or machineIdentity().key

    local remoteMachine, machineErr = M.getRemoteMachine(key)
    if type(remoteMachine) == "table" then
        remoteMachine = sanitizeMachine(remoteMachine)
        remoteMachine.key = remoteMachine.key or key
        local ok, err = writeLua(MACHINE_FILE, remoteMachine)
        if not ok then return false, err end
    elseif machineErr and machineErr ~= "not found" then
        return false, machineErr
    else
        local _, pushErr = M.pushMachine(key, current)
        if pushErr then return false, pushErr end
    end

    local remoteProfile, profileErr = M.getRemoteProfile(key)
    if type(remoteProfile) == "table" then
        if remoteProfile.format == "attacc.config.v2" then
            local ok, err = writeLua(APPS_FILE, remoteProfile.apps or {})
            if not ok then return false, err end
            local ioOk, ioErr = writeLua(IO_FILE, remoteProfile.io or {})
            if not ioOk then return false, ioErr end
            local legacyOk, legacyErr = writeLua(PROFILE_FILE, remoteProfile.legacy or {})
            if not legacyOk then return false, legacyErr end
        else
            local ok, err = writeLua(PROFILE_FILE, remoteProfile)
            if not ok then return false, err end
        end
    elseif profileErr and profileErr ~= "not found" then
        return false, profileErr
    else
        local localProfile = { format = "attacc.config.v2", apps = M.readApps(),
            io = M.readIO(), legacy = readLua(PROFILE_FILE, {}) }
        local _, pushErr = M.pushProfile(key, localProfile)
        if pushErr then return false, pushErr end
    end

    return true
end

function M.bootstrap()
    if not M.enabled() then return true, "local" end
    local ok, err = M.pullCurrent()
    if ok then return true, "synced" end
    return true, "local cache; " .. tostring(err)
end

function M.listMachines()
    local keys, err = request("list", nil)
    if not keys then return nil, err end
    local out = {}
    for _,key in ipairs(keys) do
        local machineKey = tostring(key):match("^machine:(.+)$")
        if machineKey then
            local identity, lookupErr = M.getRemoteMachine(machineKey)
            out[#out+1] = {
                key = machineKey,
                hostname = type(identity) == "table" and (identity.hostname or identity.name) or nil,
                label = type(identity) == "table" and identity.label or nil,
                network = type(identity) == "table" and identity.network or nil,
                error = lookupErr,
            }
        end
    end
    table.sort(out, function(x,y) return x.key < y.key end)
    return out
end

function M.editRemote(kind, key)
    if kind ~= "profile" and kind ~= "machine" then return false, "kind must be profile or machine" end
    if not key or key == "" then return false, "machine key required" end

    local value, err
    if kind == "profile" then value, err = M.getRemoteProfile(key)
    else value, err = M.getRemoteMachine(key) end
    if err and err ~= "not found" then return false, err end
    value = type(value) == "table" and value or {}

    local tmp = "/run/attacc/" .. kind .. "-" .. tostring(key):gsub("[^%w_.%-]", "_") .. ".lua"
    local ok, writeErr = writeLua(tmp, value)
    if not ok then return false, writeErr end

    shell.run("edit", tmp)
    local edited = readLua(tmp, nil)
    if type(edited) ~= "table" then return false, "edited file is invalid" end

    local result, pushErr
    if kind == "profile" then result, pushErr = M.pushProfile(key, edited)
    else
        edited.key = edited.key or key
        result, pushErr = M.pushMachine(key, edited)
    end
    if pushErr then return false, pushErr end
    return true
end

function M.handleCli(args)
    args = args or {}
    local cmd = args[1]
    if not cmd or cmd == "help" or cmd == "--help" then
        print("profilectl show           Full local machine configuration")
        print("profilectl info           Machine identity and network overview")
        print("profilectl reset          Reset identity and local configuration (confirmed)")
        print("profilectl status         Machine/profile overview")
        print("profilectl edit           Edit local profile")
        print("profilectl push           Upload local configuration")
        print("profilectl pull           Download stored configuration")
        print("profilectl machines       List machines in config storage")
        print("profilectl edit remote <machine-key> [profile|machine]")
        print("profilectl storage-sync   Configure synchronization")
        print("profilectl init           Interactive profile wizard (nested settings)")
        print("profilectl config               Show configuration help")
        print("profilectl config inter         Interactive category menu")
        print("profilectl config remote inter  Select stored machine, browse/edit settings")
        print("profilectl config list|show|set|unset   Edit a single parameter")
        print("profilectl reset          Reset local profile")
        return true
    end

    -- Only scalar values and string-array leaves are edited by the wizard.
    -- Other/nested values are displayed and can be edited with profilectl edit.
    local allowed = {
        ["motor.direction"] = {"-1", "1"},
        ["sensors.rpm.multiplier"] = {"-1", "1"},
        ["display.preferred"] = {"auto", "text", "ccgraphics"},
        ["redstone.mode"] = {"auto", "direct", "relay"},
        ["pocket.transport"] = {"master", "direct"},
        ["app.displayModule"] = {"steamplant", "none"},
    }
    local function pathParts(path)
        if type(path) ~= "string" then return nil end
        local parts = {}
        for part in tostring(path):gmatch("[^%.]+") do
            if not part:match("^[%a_][%w_]*$") then return nil end
            parts[#parts+1] = part
        end
        if #parts == 0 or table.concat(parts, ".") ~= path then return nil end
        return parts
    end
    local function atPath(root, parts)
        local node = root
        for _, part in ipairs(parts) do
            if type(node) ~= "table" then return nil end
            node = node[part]
        end
        return node
    end
    local function setPath(root, parts, value)
        local node = root
        for i=1,#parts-1 do
            local part = parts[i]
            if type(node[part]) ~= "table" then node[part] = {} end
            node = node[part]
        end
        node[parts[#parts]] = value
    end
    local function unsetPath(root, parts)
        local node = root
        for i=1,#parts-1 do
            node = node[parts[i]]
            if type(node) ~= "table" then return end
        end
        node[parts[#parts]] = nil
    end
    local function isStringArray(value)
        if type(value) ~= "table" then return false end
        local count = 0
        for key, item in pairs(value) do
            if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or type(item) ~= "string" then return false end
            count = count + 1
        end
        return count > 0 and count == #value
    end
    local function leaves(root, prefix, out)
        for key,value in pairs(root or {}) do
            if type(key) == "string" then
                local path = prefix == "" and key or (prefix .. "." .. key)
                if type(value) == "table" and not isStringArray(value) then
                    leaves(value, path, out)
                elseif type(value) == "string" or type(value) == "number"
                    or type(value) == "boolean" or isStringArray(value) then
                    out[#out+1] = path
                end
            end
        end
        table.sort(out)
        return out
    end
    local function printable(value)
        if isStringArray(value) then return table.concat(value, ",") end
        if type(value) == "table" then return serialize(value) end
        return tostring(value)
    end
    local function parseSetting(path, current, raw)
        if raw == "" then return nil, "empty input" end
        local choices = allowed[path]
        if choices then
            local permitted = false
            for _,v in ipairs(choices) do if raw == v then permitted = true end end
            if not permitted then return nil, "Allowed: " .. table.concat(choices, ", ") end
        end
        if path == "app.displayModule" and raw == "none" then
            return nil, "nil override cannot be persisted; use profilectl edit for disabling"
        end
        if path:match("^peripherals%.") and raw == "auto" then
            return "auto"
        end
        if type(current) == "number" then
            local n = tonumber(raw)
            if not n or n ~= n then return nil, "expected number" end
            return n
        elseif type(current) == "boolean" then
            if raw == "true" or raw == "y" or raw == "yes" then return true end
            if raw == "false" or raw == "n" or raw == "no" then return false end
            return nil, "expected true/false"
        elseif isStringArray(current) then
            local items = {}
            for item in raw:gmatch("[^,]+") do
                item = item:match("^%s*(.-)%s*$")
                if item ~= "" then items[#items+1] = item end
            end
            if #items == 0 then return nil, "expected comma-separated values" end
            return items
        elseif type(current) == "string" then
            return raw
        end
        return nil, "unsupported setting type"
    end
    local peripheralFields = {
        target = true, speedometer = true, stressometer = true,
        motor = true, accumulator = true, redstoneRelay = true,
    }
    local function effectiveLeaf(path)
        local parts = pathParts(path)
        if not parts then return nil end
        local value = atPath(config, parts)
        if value == nil and parts[1] == "peripherals" and #parts == 2
            and peripheralFields[parts[2]] and type(config.peripherals) == "table" then
            return "auto"
        end
        return value
    end
    local function settingOrigin(path)
        local parts = pathParts(path)
        if not parts then return "unknown" end
        if atPath(M.readIO(),parts) ~= nil then return "/etc/io.lua" end
        if atPath(M.readApps(),parts) ~= nil then return "/etc/apps.lua" end
        if atPath(readLua(PROFILE_FILE,{}),parts) ~= nil then return "/etc/profile.lua" end
        return "preset default"
    end
    local function allLeaves()
        local result = leaves(config, "", {})
        if type(config.peripherals) == "table" then
            for name in pairs(peripheralFields) do
                local path = "peripherals." .. name
                local found = false
                for _, existing in ipairs(result) do if existing == path then found = true break end end
                if not found then result[#result+1] = path end
            end
        end
        table.sort(result)
        return result
    end
    local function validSetting(path)
        local parts = pathParts(path)
        if not parts then return nil, nil, "invalid configuration path" end
        -- The config table already merges shipped defaults and local profile.
        local current = effectiveLeaf(path)
        if current == nil then return nil, nil, "unknown path: " .. path end
        if type(current) == "table" and not isStringArray(current) then
            return nil, nil, "select a leaf parameter, not a section: " .. path
        end
        return parts, current
    end
    local function choicesLabel(path, current)
        if allowed[path] then return table.concat(allowed[path], " / ") end
        if path:match("^peripherals%.") then return "auto / peripheral name" end
        if type(current) == "boolean" then return "true / false" end
        if type(current) == "number" then return "number" end
        if isStringArray(current) then return "comma-separated strings" end
        return "text"
    end
    local function storeSetting(path, raw)
        local parts, current, err = validSetting(path)
        if not parts then return false, err end
        local value, parseErr = parseSetting(path, current, raw)
        if parseErr then return false, parseErr end
        local profile = M.readApps()
        local ioSettings = M.readIO()
        local ioField = (path:match("^io%.") or path:match("^peripherals%.") or path:match("^redstone%.")) ~= nil
        local destination = ioField and ioSettings or profile
        if path:match("^peripherals%.") and value == "auto" then
            unsetPath(destination,parts)
        else
            setPath(destination,parts,value)
        end
        local ok, result = M.saveLayers(profile, ioSettings)
        if not ok then return false, result end
        return true, result
    end

    local function numberedMenu(title, options)
        print("")
        print("== " .. title .. " ==")
        for i,option in ipairs(options) do
            print(string.format("%2d) %s",i,option))
        end
        print(" 0) Back / Finish")
        write("Selection: ")
        local number = tonumber(read())
        if number == 0 then return nil end
        if not number or number % 1 ~= 0 or number < 1 or number > #options then
            print("Invalid selection.")
            return false
        end
        return number
    end

    local function editMenu(mode)
        print("ATTACC CONFIG " .. string.upper(mode))
        while true do
            local sections, seen = {}, {}
            for _,path in ipairs(allLeaves()) do
                local section = path:match("^([^.]+)")
                if not seen[section] then sections[#sections+1]=section; seen[section]=true end
            end
            table.sort(sections)
            local selected = numberedMenu("Categories", sections)
            if selected == nil then return end
            if selected then
                local prefix = sections[selected] .. "."
                local choices = {}
                for _,path in ipairs(allLeaves()) do
                    if path:sub(1,#prefix)==prefix then choices[#choices+1]=path end
                end
                while true do
                    local labels = {}
                    for _,path in ipairs(choices) do
                        labels[#labels+1] = path .. " = " .. printable(effectiveLeaf(path))
                    end
                    local index = numberedMenu(sections[selected],labels)
                    if index == nil then break end
                    if index then
                        local path = choices[index]
                        local _,value = validSetting(path)
                        print("Parameter : " .. path)
                        print("Purpose   : " .. configHelp.describe(path))
                        print("Current   : " .. printable(value))
                        print("Source    : " .. settingOrigin(path))
                        print("Allowed   : " .. choicesLabel(path,value))
                        write("New value [blank = keep]: ")
                        local raw = read()
                        if raw ~= "" then
                            local ok,detail = storeSetting(path,raw)
                            print(ok and ("Saved ("..tostring(detail)..")") or ("Rejected: "..tostring(detail)))
                        end
                    end
                end
            end
        end
    end

    local function remoteConfig(args)
        local machineKey = args[3]
        local command = args[4] or "show"
        if not machineKey or machineKey == "" then
            return false, "profilectl config remote <machine-key> [show|list|set|unset] ..."
        end
        local record, err = M.getRemoteProfile(machineKey)
        if err then return false, err end
        if type(record) ~= "table" then return false, "remote profile not found" end
        local bundle = record.format == "attacc.config.v2"
        local appConfig = bundle and copy(record.apps or {}) or copy(record)
        local ioConfig = bundle and copy(record.io or {}) or {}
        local function field(path)
            local parts = pathParts(path)
            if not parts then return nil,nil,"invalid parameter path" end
            local isIO = parts[1] == "io" or parts[1] == "peripherals" or parts[1] == "redstone"
            local destination = isIO and ioConfig or appConfig
            local _,localDefault = validSetting(path)
            local stored = atPath(destination,parts)
            local typed = stored ~= nil and stored or localDefault
            if typed == nil then
                return nil,nil,"unknown setting on this machine and remote profile: " .. path
            end
            if type(typed) == "table" and not isStringArray(typed) then
                return nil,nil,"expected a leaf setting, not a whole section"
            end
            return destination,parts,typed
        end
        if command == "show" or command == "list" then
            print("Remote machine: " .. tostring(machineKey))
            print("Profile format: " .. (bundle and "v2 apps/io" or "legacy"))
            if command == "show" and args[5] then
                local target,parts,problem = field(args[5])
                if not target then return false, problem end
                local override = atPath(target,parts)
                print(args[5] .. " = " .. printable(override == nil and effectiveLeaf(args[5]) or override))
            else
                print(serialize(appConfig))
                if bundle then print("IO:"); print(serialize(ioConfig)) end
            end
            return true
        end
        if command ~= "set" and command ~= "unset" then return false, "expected show/list/set/unset" end
        local path = args[5]
        local target,parts,default = field(path)
        if not target then return false,default end
        if command == "set" then
            local raw = table.concat(args," ",6)
            local value,parseErr = parseSetting(path,default,raw)
            if parseErr then return false,parseErr end
            if path:match("^peripherals%.") and value == "auto" then unsetPath(target,parts)
            else setPath(target,parts,value) end
        else
            unsetPath(target,parts)
        end
        if bundle then
            record.apps,record.io = appConfig,ioConfig
        else record = appConfig end
        local _,saveErr = M.pushProfile(machineKey,record)
        if saveErr then return false,saveErr end
        return true
    end

    local function remoteInteractive()
        local machines, err = M.listMachines()
        if not machines then print("Storage: " .. tostring(err)); return end
        if #machines == 0 then print("No saved machines in Storage."); return end
        while true do
            local labels = {}
            for _,item in ipairs(machines) do
                labels[#labels+1] = tostring(item.hostname or item.label or "(unnamed)")
                    .. " | " .. item.key .. " | " .. tostring(item.network or "?")
            end
            local chosen = numberedMenu("Stored machines", labels)
            if chosen == nil then return end
            if chosen then
                local item = machines[chosen]
                local machineKey = item.key
                while true do
                    local record, loadErr = M.getRemoteProfile(machineKey)
                    if loadErr or type(record) ~= "table" then
                        print("Cannot load " .. machineKey .. ": " .. tostring(loadErr or "not found"))
                        break
                    end
                    local bundle = record.format == "attacc.config.v2"
                    local targetApps = bundle and (record.apps or {}) or record
                    local targetIO = bundle and (record.io or {}) or {}
                    local paths = allLeaves()
                    local unique = {}
                    for _,path in ipairs(paths) do unique[path] = true end
                    for _,itemPath in ipairs(leaves(targetApps,"",{})) do unique[itemPath] = true end
                    for _,itemPath in ipairs(leaves(targetIO,"",{})) do unique[itemPath] = true end
                    paths = {}
                    for path in pairs(unique) do paths[#paths+1] = path end
                    table.sort(paths)
                    local categories, seen = {}, {}
                    for _,path in ipairs(paths) do
                        local category = path:match("^([^.]+)")
                        if category and not seen[category] then
                            categories[#categories+1] = category
                            seen[category] = true
                        end
                    end
                    table.sort(categories)
                    local categoryIndex = numberedMenu("Remote: " ..
                        tostring(item.hostname or machineKey), categories)
                    if categoryIndex == nil then break end
                    if categoryIndex then
                        local prefix = categories[categoryIndex] .. "."
                        local filtered = {}
                        for _,path in ipairs(paths) do
                            if path:sub(1,#prefix) == prefix then filtered[#filtered+1] = path end
                        end
                        while true do
                            local labels2 = {}
                            for _,path in ipairs(filtered) do
                                local parts = pathParts(path)
                                local ioField = path:match("^io%.") or path:match("^peripherals%.")
                                    or path:match("^redstone%.")
                                local remoteValue = atPath(ioField and targetIO or targetApps,parts)
                                labels2[#labels2+1] = path .. " = " ..
                                    (remoteValue == nil and "(no override)" or printable(remoteValue))
                            end
                            local param = numberedMenu(categories[categoryIndex], labels2)
                            if param == nil then break end
                            if param then
                                local path = filtered[param]
                                local parts = pathParts(path)
                                local ioField = path:match("^io%.") or path:match("^peripherals%.")
                                    or path:match("^redstone%.")
                                local remoteValue = atPath(ioField and targetIO or targetApps,parts)
                                local _,effective = validSetting(path)
                                print("Parameter : " .. path)
                                print("Purpose   : " .. configHelp.describe(path))
                                print("Remote    : " .. (remoteValue == nil and "(no override)" or printable(remoteValue)))
                        print("Source    : " .. (remoteValue == nil and "no saved override" or "remote Storage record"))
                                print("Local ref : " .. tostring(effective and printable(effective) or "(not defined here)"))
                                print("Allowed   : " .. choicesLabel(path,effective or remoteValue))
                                write("New value [blank to keep]: ")
                                local raw = read()
                                if raw ~= "" then
                                    print("Target: " .. tostring(item.hostname or machineKey) .. " [" .. machineKey .. "]")
                                    print(path .. " => " .. raw)
                                    write("Write to remote Storage record [y/N]: ")
                                    if read():lower() == "y" then
                                        local ok, saveErr = remoteConfig({"config","remote",machineKey,"set",path,raw})
                                        print(ok and "Remote record saved; target must pull to apply." or
                                            ("Rejected: " .. tostring(saveErr)))
                                        if ok then break end
                                    else print("Cancelled.") end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if cmd == "config" then
        local action = args[2] or "help"
        if action == "help" then
            print("profilectl config inter")
            print("profilectl config list")
            print("profilectl config show <section.key>")
            print("profilectl config set <section.key> <value>")
            print("profilectl config unset <section.key>")
            print("profilectl config remote inter")
            print("profilectl config remote <machine-key> ...")
        elseif action == "remote" and args[3] == "inter" then
            remoteInteractive()
        elseif action == "remote" then
            local ok, detail = remoteConfig(args)
            if not ok then error(detail) end
            print("Remote configuration operation completed.")
        elseif action == "inter" then
            editMenu("interactive")
        elseif action == "list" then
            for _, path in ipairs(allLeaves()) do
                local value = effectiveLeaf(path)
                print(path .. " = " .. printable(value) .. " (" .. choicesLabel(path, value) .. ")")
                print("    " .. configHelp.describe(path) .. " | " .. settingOrigin(path))
            end
        elseif action == "show" then
            local path = args[3]
            local parts, current, err = validSetting(path)
            if not parts then error(err) end
            local stored = atPath(M.readIO(), parts)
                or atPath(M.readApps(), parts)
                or atPath(readLua(PROFILE_FILE, {}), parts)
            print(path .. " effective: " .. printable(current))
            print("Local override: " .. (stored == nil and "(defaults)" or printable(stored)))
            print("Allowed: " .. choicesLabel(path, current))
            print("Purpose: " .. configHelp.describe(path))
            print("Source: " .. settingOrigin(path))
        elseif action == "set" then
            if not args[3] or not args[4] then error("Usage: profilectl config set <path> <value>") end
            local ok, result = storeSetting(args[3], table.concat(args, " ", 4))
            if not ok then error(result) end
            print("Saved " .. args[3] .. " (" .. tostring(result) .. "). Restart application to apply.")
        elseif action == "unset" then
            local path = args[3]
            local parts, _, err = validSetting(path)
            if not parts then error(err) end
            local profile = M.readApps()
            local ioSettings = M.readIO()
            if (path:match("^io%.") or path:match("^peripherals%.") or path:match("^redstone%.")) then unsetPath(ioSettings, parts)
            else unsetPath(profile, parts) end
            local ok, result = M.saveLayers(profile, ioSettings)
            if not ok then error(result) end
            print("Removed local override " .. path .. "; shipped defaults apply after restart.")
        else
            print("profilectl config list")
            print("profilectl config show <path>")
            print("profilectl config set <path> <value>")
            print("profilectl config unset <path>")
            error("unknown config command")
        end
        return true
    end

    if cmd == "info" or cmd == "status" then
        local m = require("lib.machine").get()
        print("ATTACC MACHINE")
        print("Hostname   : " .. tostring(m.hostname))
        print("Machine key: " .. tostring(m.key))
        print("Label      : " .. tostring(m.label))
        print("Network    : " .. tostring(m.network))
        print("Role       : " .. tostring(m.role))
        print("Computer ID: " .. tostring(m.computerId))
        print("Preset     : " .. tostring(m.preset))
        print("Applications: " .. table.concat(m.apps or {}, ", "))
        print("Modules     : " .. table.concat(m.modules or {}, ", "))
        print("Storage host: " .. tostring(storageConfig().targetMachine or "(not set)"))
        return true
    end

    if cmd == "reset" then
        local key = require("lib.machine").get().key
        print("This deletes local machine identity and all app/IO overrides.")
        print("Storage server data and remote backups will NOT be deleted.")
        write("Type the machine key [" .. tostring(key) .. "] to confirm: ")
        if read() ~= key then print("Reset cancelled.") return true end
        for _,path in ipairs({MACHINE_FILE,APPS_FILE,IO_FILE,PROFILE_FILE}) do
            if fs.exists(path) then fs.delete(path) end
        end
        print("Local configuration reset. Reboot to apply defaults.")
        return true
    end

    if cmd == "init" then
        print("ATTACC INITIAL SETUP")
        print("Configure the logical machine identity first.")
        local machine = require("lib.machine").get()
        local identity = readLua(MACHINE_FILE,{})
        for _, field in ipairs({"key","hostname","label","network"}) do
            local current = identity[field] or machine[field]
            write("  " .. field .. " [" .. tostring(current or "") .. "]: ")
            local value = read()
            if value ~= "" then identity[field] = value end
        end
        local ok,detail = M.saveMachine(identity)
        if not ok then error(detail) end
        print("Machine identity saved ("..tostring(detail)..").")
        editMenu("initial setup")
        print("Initial setup complete. Restart to load the configuration.")
        return true
    end

    if cmd == "pull" or cmd == "sync" then
        local ok, err = M.pullCurrent()
        print(ok and "Configuration synchronized from Storage." or ("Sync failed: " .. tostring(err)))
        return true
    end

    if cmd == "show" then
        local function view(path)
            if not fs.exists(path) then return {} end
            local ok, data = pcall(dofile, path)
            return ok and type(data) == "table" and data or {}
        end
        local identity = view(MACHINE_FILE)
        local profile = view(PROFILE_FILE)
        local cfg = view(STORAGE_FILE)
        print("ATTACC MACHINE CONFIGURATION")
        print("Effective application configuration (defaults + profile)")
        print(serialize(config))
        print("Machine identity (/etc/machine.lua)")
        print(serialize(identity))
        print("Apps overrides (/etc/apps.lua)")
        print(serialize(M.readApps()))
        print("IO overrides (/etc/io.lua)")
        print(serialize(M.readIO()))
        print("Legacy profile (/etc/profile.lua)")
        print(serialize(profile))
        print("Storage client (/etc/storage.lua)")
        print(serialize(cfg))
        return true
    end

    if cmd == "push" then
        local ok, err = M.pushCurrent()
        print(ok and "Local configuration pushed to Storage." or ("Push failed: " .. tostring(err)))
        return true
    end

    if cmd == "edit" and args[2] == "remote" then
        local ok, err = M.editRemote(args[4] or "profile", args[3])
        print(ok and "Remote configuration updated." or ("Remote edit failed: " .. tostring(err)))
        return true
    end

    if cmd == "remote" then
        local key = args[2]
        local kind = args[3] or "profile"
        local ok, err = M.editRemote(kind, key)
        print(ok and ("Remote " .. kind .. " updated for " .. tostring(key))
            or ("Remote edit failed: " .. tostring(err)))
        return true
    end

    if cmd == "machines" then
        local machines, err = M.listMachines()
        if not machines then print("Storage error: " .. tostring(err)); return true end
        local cfg = storageConfig()
        print("Storage host: " .. tostring(cfg.targetMachine or "(not configured)"))
        print("Namespace   : " .. tostring(cfg.namespace))
        print("Saved machine configurations: " .. tostring(#machines))
        for _, entry in ipairs(machines) do
            print("  " .. tostring(entry.hostname or entry.label or "(unknown hostname)")
                .. " | " .. entry.key .. " | " .. tostring(entry.network or "?"))
        end
        if #machines == 0 then print("(no synchronized machines)") end
        return true
    end

    if cmd == "storage-sync" then
        local cfg = storageConfig()
        write("Enable config sync [" .. (cfg.enabled and "Y/n" or "y/N") .. "]: ")
        local answer = read():lower()
        if answer ~= "" then cfg.enabled = answer=="y" or answer=="yes" end

        print("Storage host  : " .. tostring(cfg.targetMachine or "(not selected)"))
        print("Namespace     : " .. tostring(cfg.namespace or NAMESPACE))
        print("Change host/namespace with storagectl use <machine-key> [namespace].")

        write("Timeout seconds [" .. tostring(cfg.timeout or 2) .. "]: ")
        local timeout = read()
        if timeout ~= "" then cfg.timeout = tonumber(timeout) or cfg.timeout end

        local ok, err = writeLua(STORAGE_FILE, cfg)
        print(ok and ("Saved " .. STORAGE_FILE) or ("Error: " .. tostring(err)))
        return true
    end

    return false
end

return M
