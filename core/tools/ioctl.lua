local ioRegistry = require("lib.io_registry")

local args = { ... }
local cmd = args[1]
if not cmd or cmd == "help" or cmd == "--help" then
    print("ioctl list")
    print("ioctl init  - configure application hardware requirements")
    print("ioctl check - check required and optional hardware")
    print("ioctl hardware")
    print("ioctl bind  - guided physical hardware binding")
    print("ioctl show <name>")
    print("ioctl read <name>")
    print("ioctl write <name> <value>")
    return
end
-- Hardware-only configuration store. No legacy profiles or global app config.
local profileStore={}
function profileStore.readIO()
    if not fs.exists("/etc/io.lua") then return {} end
    local ok,config=pcall(dofile,"/etc/io.lua")
    if not ok or type(config)~="table" then error("invalid /etc/io.lua") end
    return config
end
function profileStore.readApps() return {} end
function profileStore.saveLayers(_,io)
    if not fs.exists("/etc") then fs.makeDir("/etc") end
    local tmp="/etc/io.lua.new"
    local h=fs.open(tmp,"w")
    if not h then return false,"cannot open /etc/io.lua.new" end
    h.write("return "..textutils.serialize(io).."\n")
    h.close()
    local backup="/etc/io.lua.bak"
    if fs.exists(backup) then fs.delete(backup) end
    if fs.exists("/etc/io.lua") then fs.move("/etc/io.lua",backup) end
    local moved,err=pcall(fs.move,tmp,"/etc/io.lua")
    if not moved then
        if fs.exists(backup) then fs.move(backup,"/etc/io.lua") end
        return false,tostring(err)
    end
    if fs.exists(backup) then fs.delete(backup) end
    return true
end
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
    local name = prompt("Logical binding name (alias for this input/output)",nil)
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

local function setupRequirements()
    local requirements = ioRegistry.requirements()
    local roles = {}
    for role in pairs(requirements) do roles[#roles+1] = role end
    table.sort(roles)
    if #roles == 0 then
        print("No hardware requirements declared by this application.")
        print("Use ioctl bind for an independent logical I/O binding.")
        return
    end
    print("ATTACC HARDWARE INITIALIZATION")
    print("Choose a peripheral for each application hardware role.")
    print("Use 0 for automatic selection. Required hardware must be available.")
    local stored = profileStore.readIO()
    stored.io = stored.io or {}
    stored.io.bindings = stored.io.bindings or {}
    local pending = {}
    for _,role in ipairs(roles) do
        local requirement = requirements[role]
        local choices = ioRegistry.candidates(role, requirement)
        print("")
        print(role .. " [" .. tostring(requirement.type) .. "] " ..
            (requirement.required and "REQUIRED" or "OPTIONAL"))
        print("  " .. tostring(requirement.description or "Hardware required by the application"))
        if requirement.type ~= "redstone" then print("  0) Automatic") end
        for index,name in ipairs(choices) do print(string.format("  %d) %s",index,name)) end
        if not requirement.required then print("  s) Skip / unavailable") end
        local old = stored.io.bindings[role]
        if old then print("Existing: " .. tostring(old.side or old.peripheral or "unassigned")) end
        local selection
        repeat
            write("Selection [0]: ")
            selection = read()
            if selection == "" then selection = "0" end
            local n = tonumber(selection)
            if selection == "s" and not requirement.required then break end
            if requirement.type == "redstone" and n == 0 then
                print("Redstone requires an explicit side.")
            elseif n and n >= 0 and n <= #choices and n%1 == 0 then break end
            print("Invalid selection.")
        until false
        if requirement.type == "redstone" then
            local side = selection == "s" and nil
                or (tonumber(selection) == 0 and nil or choices[tonumber(selection)])
            local relays={}
            for _,peripheralName in ipairs(peripheral.getNames()) do
                for _,kind in ipairs({peripheral.getType(peripheralName)}) do
                    if kind=="redstone_relay" then
                        relays[#relays+1]=peripheralName
                        break
                    end
                end
            end
            table.sort(relays)
            print("Redstone output device:")
            print("  0) Computer built-in redstone")
            for i,relayName in ipairs(relays) do
                print("  "..i..") "..relayName)
            end
            local oldRelay=old and old.relay or nil
            local defaultRelay=0
            for i,relayName in ipairs(relays) do
                if relayName==oldRelay then defaultRelay=i end
            end
            local relayChoice
            repeat
                write("Device ["..defaultRelay.."]: ")
                local raw=read()
                relayChoice=raw=="" and defaultRelay or tonumber(raw)
                if relayChoice and relayChoice%1==0
                    and relayChoice>=0 and relayChoice<=#relays then break end
                printError("Invalid redstone device")
            until false
            pending[role] = {kind="redstone",direction=requirement.direction or "input",side=side,
                relay=relayChoice>0 and relays[relayChoice] or nil,
                invert=requirement.invert == true or (old and old.invert == true) or false,
                readOutput=requirement.readOutput == true or (old and old.readOutput == true) or false}
            if not side and requirement.required then print("ERROR: choose a redstone side.") end
        elseif selection == "s" then
            pending[role] = {peripheral = "auto", type = requirement.type,
                direction = requirement.direction or "input", kind="peripheral", disabled=true}
        else
            local n = tonumber(selection)
            pending[role] = {peripheral = n == 0 and "auto" or choices[n],
                type = requirement.type,direction=requirement.direction or "input",kind="peripheral",
                method=old and old.method or nil, args=old and old.args or nil,
                multiplier=old and old.multiplier or nil, offset=old and old.offset or nil,
                invert=old and old.invert or nil}
            if n == 0 and #choices ~= 1 then
                print((requirement.required and "ERROR" or "WARNING") ..
                    ": Auto requires exactly one matching peripheral.")
            end
        end
        -- SDK application roles bind whole devices, not individual methods.
        -- The application selects methods through app:call(role, method).
        -- Clear any method-level legacy binding when reconfiguring a role.
        if pending[role].kind=="peripheral" then
            pending[role].method=nil
            pending[role].args=nil
        end
        if old and old.peripheral and old.peripheral ~= pending[role].peripheral then
            print("Previous selection: " .. tostring(old.peripheral))
        end
    end
    print("")
    print("Planned bindings:")
    for _,role in ipairs(roles) do
        print("  " .. role .. " -> " .. tostring(pending[role].relay and (pending[role].relay..":"..tostring(pending[role].side)) or pending[role].side or pending[role].peripheral or "unassigned"))
    end
    write("Save to /etc/io.lua [y/N]: ")
    if read():lower() ~= "y" then print("Cancelled."); return end
    for role,binding in pairs(pending) do stored.io.bindings[role] = binding end
    local ok,err = profileStore.saveLayers(profileStore.readApps(),stored)
    if not ok then error(err) end
    print("Saved. Reboot the application, then run ioctl check.")
end

local function checkRequirements()
    local statuses,ready = ioRegistry.validateRequirements()
    if #statuses == 0 then print("No hardware requirements declared."); return end
    for _,status in ipairs(statuses) do
        print(string.upper(status.level) .. " " .. status.role .. " => " ..
            tostring(status.peripheral or status.error))
    end
    if not ready then printError("Required hardware missing: run ioctl init.") end
end

if cmd == "init" then setupRequirements(); return end
if cmd == "check" then checkRequirements(); return end
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
        print("No explicit logical I/O bindings configured.")
        checkRequirements()
        print("Run ioctl init to associate hardware roles with discovered devices.")
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
