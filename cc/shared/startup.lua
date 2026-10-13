-- Native CC runtime bootstrap.
-- CraftOS remains the primary shell; the selected preset application is opened
-- in a separate multishell tab. No service graph or SSH daemon is started here.

local PRESET_FILE = "/etc/preset"

local apps = {
    collector = { program = "collectord.lua", title = "collector" },
    controller = { program = "controllerd.lua", title = "controller" },
    master = { program = "supervisord.lua", title = "master" },
    pocket = { program = "clientd.lua", title = "pocket" },
    workstation = { program = "workstationd.lua", title = "workstation" },
}

local function readPreset()
    if not fs.exists(PRESET_FILE) then return nil end
    local h = fs.open(PRESET_FILE, "r")
    if not h then return nil end
    local value = h.readAll()
    h.close()
    return value and value:gsub("%s+$", "") or nil
end

local function launch(program, title)
    if not fs.exists(program) then
        printError("Native runtime: missing " .. tostring(program))
        return nil
    end

    if shell.openTab then
        local id = shell.openTab(program)
        if id and multishell and multishell.setTitle then
            pcall(multishell.setTitle, id, title)
        end
        return id
    end

    -- Standard computers have no multishell. Fall back to running the app in
    -- the current terminal so the same preset remains usable.
    shell.run(program)
    return nil
end

local preset = readPreset()
local app = preset and apps[preset] or nil

if not app then
    printError("Native runtime: unknown or missing preset in " .. PRESET_FILE)
    print("Run install to configure a preset.")
    return
end

local appTab
if preset == "pocket" then
    -- Pocket owns its built-in screen. Run the UI in the current terminal so
    -- it has focus immediately and receives input events directly.
    shell.run(app.program)
else
    appTab = launch(app.program, app.title)
    if appTab then
        print("Native runtime: " .. app.title .. " started in tab " .. tostring(appTab))
    end
end

-- The hosted bridge remains optional and independent from the main application.
-- It is only started on a supervisor when local Web configuration exists.
if preset == "master" and fs.exists("/etc/webbridge.lua") and fs.exists("webbridge.lua") then
    local webTab = launch("webbridge.lua", "webbridge")
    if webTab then
        print("Native runtime: web bridge started in tab " .. tostring(webTab))
    end
end
