-- Native AttaCC runtime bootstrap.

local PRESET_FILE = "/etc/preset"

local apps = {
    steamplant = { program = "steamplant.lua", title = "steamplant" },
    master = { program = "master.lua", title = "master" },
    pocket = { program = "pocket.lua", title = "pocket" },
    workstation = { program = "workstation.lua", title = "workstation" },
    dashboard = { program = "dashboard.lua", title = "dashboard" },
}

local function readPreset()
    if not fs.exists(PRESET_FILE) then return nil end
    local h = fs.open(PRESET_FILE, "r")
    if not h then return nil end
    local value = h.readAll()
    h.close()
    return value and value:gsub("%s+$", "") or nil
end

local function bootLog(level, message)
    local ok, runtime = pcall(require, "lib.runtime")
    if ok and runtime and runtime.log then
        pcall(runtime.log, "startup", level, message)
    end
end

local function bootHealth(status, message)
    local ok, runtime = pcall(require, "lib.runtime")
    if ok and runtime and runtime.set then
        pcall(runtime.set, "startup", status, { message = tostring(message or "") })
    end
end

local publishLifecycle

local function launch(program, title, ...)
    if not fs.exists(program) then
        printError("AttaCC: missing " .. tostring(program))
        bootLog("error", "Missing startup program: " .. tostring(program))
        bootHealth("error", "Missing program " .. tostring(program))
        return nil
    end

    if shell.openTab then
        local id = shell.openTab(program, ...)
        if id then publishLifecycle("APP_START", "Started " .. tostring(title)) end
        if id and multishell and multishell.setTitle then
            pcall(multishell.setTitle, id, title)
        end
        return id
    end

    publishLifecycle("APP_START", "Started " .. tostring(title))
    local ok = shell.run(program, ...)
    if not ok then
        bootLog("error", "Program exited unsuccessfully: " .. tostring(program))
        bootHealth("error", "Program failed: " .. tostring(program))
    end
    return nil
end

local okProfileStore, profileStore = pcall(require, "lib.profile_store")
if okProfileStore and profileStore then
    local ok, detail = profileStore.bootstrap()
    if detail and detail ~= "local" and detail ~= "synced" then
        print("AttaCC config: " .. tostring(detail))
    end
end

-- Keep completion configuration in the general profile; never erase the CraftOS path.
local okShellProfile, shellProfile = pcall(dofile, "/etc/profile.lua")
local shellSettings = okShellProfile and type(shellProfile) == "table" and shellProfile.shell or {}
if not shellSettings or shellSettings.completion ~= false then
    local okCompletion, completion = pcall(require, "lib.shell_completion")
    if okCompletion and completion then
        local okInstall, why = completion.install()
        if not okInstall and why then print("AttaCC completion: "..tostring(why)) end
    end
end

-- Report the machine boot and process launches to the Master event stream.
publishLifecycle = function(code, description)
    local ok, err = pcall(function()
        local config = require("lib.config")
        local protocol = require("lib.protocol")
        local machine = require("lib.machine").get()
        local modem = protocol.findWirelessModem()
        if not modem then return end
        protocol.send(modem, config.channels.events or 4247, {
            type = "module_event", network = machine.network,
            module = "core.runtime", machine = machine.key,
            hostname = machine.hostname, source = machine.key,
            code = code, level = "info", message = description,
            timestamp = protocol.now(),
        })
    end)
    if not ok then
        printError("AttaCC lifecycle: " .. tostring(err))
        bootLog("warn", "Lifecycle event unavailable: " .. tostring(err))
    end
end

bootLog("info", "CraftOS startup started")
bootHealth("starting", "Reading machine preset")
publishLifecycle("MACHINE_BOOT", "CraftOS boot / AttaCC startup")

local preset = readPreset()
local app = preset and apps[preset] or nil
if not app and fs.exists("/etc/preset_app.lua") then
    local ok, custom = pcall(dofile, "/etc/preset_app.lua")
    if ok and type(custom)=="table" and custom.preset == preset
        and type(custom.program)=="string" and custom.program:match("^[%w_./-]+$")
        and fs.exists(custom.program) then
        app = { program = custom.program, title = preset }
    end
end

if not app then
    printError("AttaCC: unknown or missing preset in " .. PRESET_FILE)
    bootLog("error", "Unknown or missing startup preset: " .. tostring(preset))
    bootHealth("error", "Invalid preset: " .. tostring(preset))
    print("Run install to configure a preset.")
    return
end

bootLog("info", "Using preset: " .. tostring(preset) .. "; program: " .. tostring(app.program))
bootHealth("ready", "Configured preset: " .. tostring(preset))
local hasStorage = fs.exists("storagehost.lua")
local hasWeb = preset == "master"
    and fs.exists("/etc/webbridge.lua")
    and fs.exists("webbridge.lua")

-- Standard Computers have no multishell. Run continuous capabilities beside
-- the application with CraftOS parallel coroutines.
if not shell.openTab then
    local jobs = {
        function()
            publishLifecycle("APP_START", "Started " .. tostring(app.title))
            local ok = shell.run(app.program)
            if not ok then
                bootLog("error", "Main application failed: " .. tostring(app.program))
                bootHealth("error", "Main app failed: " .. tostring(app.program))
            end
        end,
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
    publishLifecycle("APP_START", "Started " .. tostring(app.title))
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
