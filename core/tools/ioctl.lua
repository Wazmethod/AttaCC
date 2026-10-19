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

-- For any redstone binding, choose the output/input block first; each
-- block exposes its own six faces. This also supports CC:Tweaked relays.
local function selectRedstoneDevice(oldRelay, allowSkip)
    local relays={}
    for _,name in ipairs(peripheral.getNames()) do
        for _,kind in ipairs({peripheral.getType(name)}) do
            if kind=="redstone_relay" then
                relays[#relays+1]=name
                break
            end
        end
    end
    table.sort(relays)
    print("Redstone device (input/output):")
    print("  0) Computer built-in redstone")
    for i,name in ipairs(relays) do
        print(string.format("  %d) %s",i,name))
    end
    if allowSkip then print("  s) Skip optional role") end
    local default=0
    if oldRelay then
        for i,name in ipairs(relays) do
            if name==oldRelay then default=i;break end
        end
    end
    while true do
        write("Device ["..default.."]: ")
        local answer=read()
        if answer=="" then answer=tostring(default) end
        if allowSkip and answer:lower()=="s" then return nil,true end
        local selection=tonumber(answer)
        if selection and selection%1==0 and selection>=0 and selection<=#relays then
            return selection==0 and nil or relays[selection],false
        end
        printError("Invalid redstone device")
    end
end

local function selectRedstoneSide(oldSide)
    local sides={"top","bottom","left","right","front","back"}
    local default=6
    for i,side in ipairs(sides) do
        if side==oldSide then default=i;break end
    end
    print("Redstone face (relative to the selected device):")
    for i,side in ipairs(sides) do
        print(string.format("  %d) %s",i,side))
    end
    while true do
        write("Side ["..default.."="..sides[default].."]: ")
        local answer=read()
        if answer=="" then answer=tostring(default) end
        local index=tonumber(answer)
        if index and index%1==0 and sides[index] then return sides[index] end
        for _,side in ipairs(sides) do
            if answer==side then return side end
        end
        printError("Invalid redstone side")
    end
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
        binding.relay=selectRedstoneDevice(nil,false)
        binding.side=selectRedstoneSide(nil)
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
    local requirements=ioRegistry.requirements()
    local roles={}
    for role in pairs(requirements) do roles[#roles+1]=role end
    table.sort(roles)
    if #roles==0 then
        print("No hardware requirements declared by this application.")
        print("Use ioctl bind for an independent logical I/O binding.")
        return
    end
    print("ATTACC HARDWARE INITIALIZATION")
    print("Choose the device first, then the side for each redstone role.")
    local stored=profileStore.readIO()
    stored.io=stored.io or {}
    stored.io.bindings=stored.io.bindings or {}
    local pending={}
    for _,role in ipairs(roles) do
        local requirement=requirements[role]
        local old=stored.io.bindings[role]
        print("")
        print(role.." ["..tostring(requirement.type).."] "..
            (requirement.required and "REQUIRED" or "OPTIONAL"))
        print("  "..tostring(requirement.description or "Hardware required by the application"))
        if old then
            print("Existing: "..tostring(old.relay and
                (old.relay..":"..tostring(old.side)) or old.side or
                old.peripheral or "unassigned"))
        end
        if requirement.type=="redstone" then
            local relay,skip=selectRedstoneDevice(old and old.relay,not requirement.required)
            if skip then
                pending[role]={kind="redstone",direction=requirement.direction or "input",
                    disabled=true}
            else
                local side=selectRedstoneSide(old and old.side)
                pending[role]={kind="redstone",direction=requirement.direction or "input",
                    side=side,relay=relay,
                    invert=requirement.invert==true or (old and old.invert==true) or false,
                    readOutput=requirement.readOutput==true or
                        (old and old.readOutput==true) or false}
            end
        else
            local choices=ioRegistry.candidates(role,requirement)
            if requirement.type~="redstone_relay" then print("  0) Automatic") end
            for i,name in ipairs(choices) do
                print(string.format("  %d) %s",i,name))
            end
            if not requirement.required then print("  s) Skip / unavailable") end
            local selectedDefault=nil
            if old then
                for i,name in ipairs(choices) do
                    if name==old.peripheral then selectedDefault=i;break end
                end
            end
            local selection
            while true do
                write("Selection"..(selectedDefault and (" ["..selectedDefault.."]") or "")..": ")
                selection=read()
                if selection=="" then
                    selection=selectedDefault and tostring(selectedDefault) or "0"
                end
                local n=tonumber(selection)
                if selection=="s" and not requirement.required then break end
                if requirement.type=="redstone_relay" and n==0 then
                    printError("Select a specific Redstone Relay")
                elseif n and n%1==0 and n>=0 and n<=#choices then break
                else printError("Invalid selection") end
            end
            if selection=="s" then
                pending[role]={peripheral="auto",type=requirement.type,
                    direction=requirement.direction or "input",kind="peripheral",disabled=true}
            else
                local n=tonumber(selection)
                pending[role]={peripheral=n==0 and "auto" or choices[n],
                    type=requirement.type,direction=requirement.direction or "input",
                    kind="peripheral",invert=old and old.invert or nil}
                if n==0 and #choices~=1 then
                    print((requirement.required and "ERROR" or "WARNING")..
                        ": Auto requires exactly one matching peripheral.")
                end
            end
        end
    end
    print("")
    print("Planned bindings:")
    for _,role in ipairs(roles) do
        local binding=pending[role]
        local device=binding.relay and binding.relay or
            (binding.kind=="redstone" and "computer" or binding.peripheral or "unassigned")
        local target=binding.disabled and "SKIPPED" or
            (binding.kind=="redstone" and (device..":"..binding.side) or device)
        print("  "..role.." -> "..target)
        if binding.kind=="redstone" and not binding.disabled then
            print("    invert="..tostring(binding.invert)..
                " readOutput="..tostring(binding.readOutput))
        end
    end
    write("Save to /etc/io.lua [y/N]: ")
    if read():lower()~="y" then print("Cancelled.");return end
    for role,binding in pairs(pending) do stored.io.bindings[role]=binding end
    local ok,err=profileStore.saveLayers(profileStore.readApps(),stored)
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
