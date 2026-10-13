-- Native AttaCC runtime bootstrap.

local PRESET_FILE = "/etc/preset"

local apps = {
    steamplant = { program = "steamplant.lua", title = "steamplant" },
    master = { program = "master.lua", title = "master" },
    pocket = { program = "pocket.lua", title = "pocket" },
    workstation = { program = "workstation.lua", title = "workstation" },
}

local function readPreset()
    if not fs.exists(PRESET_FILE) then return nil end
    local h = fs.open(PRESET_FILE, "r")
    if not h then return nil end
    local value = h.readAll()
    h.close()
    return value and value:gsub("%s+$", "") or nil
end

local function launch(program, title, ...)
    if not fs.exists(program) then
        printError("AttaCC: missing " .. tostring(program))
        return nil
    end

    if shell.openTab then
        local id = shell.openTab(program, ...)
        if id and multishell and multishell.setTitle then
            pcall(multishell.setTitle, id, title)
        end
        return id
    end

    shell.run(program, ...)
    return nil
end

local preset = readPreset()
local app = preset and apps[preset] or nil

if not app then
    printError("AttaCC: unknown or missing preset in " .. PRESET_FILE)
    print("Run install to configure a preset.")
    return
end

local hasStorage = fs.exists("storagehost.lua")
local hasWeb = preset == "master"
    and fs.exists("/etc/webbridge.lua")
    and fs.exists("webbridge.lua")

-- Standard Computers have no multishell. Run continuous capabilities beside
-- the application with CraftOS parallel coroutines.
if not shell.openTab then
    local jobs = {
        function() shell.run(app.program) end,
    }

    if hasStorage then
        table.insert(jobs, function() shell.run("storagehost.lua", "--quiet") end)
    end

    if hasWeb then
        table.insert(jobs, function() shell.run("webbridge.lua") end)
    end

    parallel.waitForAny(table.unpack(jobs))
    return
end

-- Pocket owns its built-in terminal and therefore stays in the current tab.
-- Optional background capabilities are launched first in their own tabs.
if preset == "pocket" then
    if hasStorage then launch("storagehost.lua", "storage") end
    shell.run(app.program)
    return
end

local appTab = launch(app.program, app.title)
if appTab then
    print("AttaCC: " .. app.title .. " started in tab " .. tostring(appTab))
end

if hasStorage then
    local storageTab = launch("storagehost.lua", "storage")
    if storageTab then
        print("AttaCC: storage host started in tab " .. tostring(storageTab))
    end
end

if hasWeb then
    local webTab = launch("webbridge.lua", "webbridge")
    if webTab then
        print("AttaCC: web bridge started in tab " .. tostring(webTab))
    end
end
