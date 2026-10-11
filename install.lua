-- CC Infrastructure installer/updater
-- Repository: Wazmethod/steamplant-cc
-- Works with public repositories, or private repositories with a fine-grained
-- GitHub token having read-only Contents access to this repository.

local OWNER = "Wazmethod"
local REPO = "steamplant-cc"
local REF = "dev"

local presets = {
    collector = {
        "main.lua",
        "systemctl.lua",
        "ioctl.lua",
        "profilectl.lua",
        "touchtest.lua",
        "machinectl.lua",
        "startup.lua",
        "lib/config.lua",
        "lib/runtime.lua",
        "lib/services.lua",
        "lib/io_registry.lua",
        "lib/controller.lua",
        "lib/io.lua",
        "lib/protocol.lua",
        "lib/machine.lua",
        "lib/nodes.lua",
        "lib/module_router.lua",
        "lib/telemetry.lua",
        "lib/display.lua",
        "lib/ui.lua",
        "lib/ui_graphics.lua",
        "modules/steamplant.lua",
    },
    master = {
        "main.lua",
        "systemctl.lua",
        "profilectl.lua",
        "machinectl.lua",
        "startup.lua",
        "lib/config.lua",
        "lib/runtime.lua",
        "lib/services.lua",
        "lib/protocol.lua",
        "lib/machine.lua",
        "lib/nodes.lua",
        "lib/ui.lua",
        "lib/display.lua",
        "lib/ui_graphics.lua",
        "webbridge.lua",
        "web.example.lua",
    },
    pocket = {
        "main.lua",
        "systemctl.lua",
        "profilectl.lua",
        "machinectl.lua",
        "startup.lua",
        "lib/config.lua",
        "lib/runtime.lua",
        "lib/services.lua",
        "lib/protocol.lua",
        "lib/machine.lua",
        "lib/nodes.lua",
        "lib/ui.lua",
        "lib/display.lua",
        "lib/ui_graphics.lua",
    },
    controller = {
        "main.lua",
        "systemctl.lua",
        "ioctl.lua",
        "profilectl.lua",
        "machinectl.lua",
        "startup.lua",
        "lib/config.lua",
        "lib/runtime.lua",
        "lib/services.lua",
        "lib/io_registry.lua",
        "lib/protocol.lua",
        "lib/machine.lua",
        "lib/nodes.lua",
        "lib/module_router.lua",
    },
}

local idDefaults = {
    [0] = "collector",
    [1] = "master",
    [2] = "pocket",
}

local function urlencodePath(path)
    -- Our repository paths only contain URL-safe characters at present.
    return path
end

local function headers(token)
    local h = {
        ["Accept"] = "application/vnd.github.raw+json",
        ["X-GitHub-Api-Version"] = "2022-11-28",
        ["User-Agent"] = "CC-Tweaked-Infra",
    }
    if token and token ~= "" then
        h["Authorization"] = "Bearer " .. token
    end
    return h
end

local function fetchFile(repoPath, token)
    local url
    local requestHeaders = nil

    -- Public repository: use raw.githubusercontent.com instead of the GitHub
    -- Contents API. This avoids burning the unauthenticated API rate limit
    -- (60 requests/hour per public IP) every time the installer downloads files.
    if not token or token == "" then
        url = "https://raw.githubusercontent.com/" .. OWNER .. "/" .. REPO
            .. "/" .. REF .. "/" .. urlencodePath(repoPath)
            .. "?cb=" .. tostring(os.epoch("utc"))
    else
        -- Keep authenticated API support in case the repository becomes private.
        url = "https://api.github.com/repos/" .. OWNER .. "/" .. REPO
            .. "/contents/" .. urlencodePath(repoPath) .. "?ref=" .. REF
        requestHeaders = headers(token)
    end

    local response, err = http.get(url, requestHeaders)
    if not response then
        return nil, err or "HTTP request failed"
    end

    local code = response.getResponseCode()
    local body = response.readAll()
    response.close()

    if code < 200 or code >= 300 then
        return nil, "GitHub HTTP " .. tostring(code) .. ": " .. tostring(body)
    end

    return body
end

local function choosePreset()
    local default = idDefaults[os.getComputerID()]
    print("Computer ID: " .. tostring(os.getComputerID()))
    if default then
        print("Preset suggested: " .. default)
        write("Use this preset package? [Y/n] ")
        local answer = read()
        if answer == "" or answer:lower() == "y" or answer:lower() == "yes" then
            return default
        end
    end

    print("Select runtime preset package:")
    print("  1) collector")
    print("  2) master")
    print("  3) pocket")
    print("  4) controller")
    write("> ")
    local answer = read()
    if answer == "1" then return "collector" end
    if answer == "2" then return "master" end
    if answer == "3" then return "pocket" end
    if answer == "4" then return "controller" end
    error("Invalid preset package")
end

local function ensureParent(path)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
end

local function writeFile(path, content)
    ensureParent(path)
    local tmp = path .. ".new"
    local f = fs.open(tmp, "w")
    if not f then error("Cannot open " .. tmp) end
    f.write(content)
    f.close()

    if fs.exists(path) then fs.delete(path) end
    fs.move(tmp, path)
end

local function luaQuote(value)
    return string.format("%q", tostring(value or ""))
end

local function writeMachineLocal(value)
    local lines = {
        "return {",
        "    key = " .. luaQuote(value.key) .. ",",
        "    name = " .. luaQuote(value.name) .. ",",
        "    label = " .. luaQuote(value.label) .. ",",
        "    network = " .. luaQuote(value.network) .. ",",
        "    networkLabel = " .. luaQuote(value.networkLabel) .. ",",
    }

    if value.role then
        table.insert(lines, "    role = " .. luaQuote(value.role) .. ",")
    end

    if type(value.modules) == "table" then
        table.insert(lines, "    modules = {")
        for _, moduleName in ipairs(value.modules) do
            table.insert(lines, "        " .. luaQuote(moduleName) .. ",")
        end
        table.insert(lines, "    },")
    end

    if type(value.tags) == "table" then
        table.insert(lines, "    tags = {")
        for _, tag in ipairs(value.tags) do
            table.insert(lines, "        " .. luaQuote(tag) .. ",")
        end
        table.insert(lines, "    },")
    end

    table.insert(lines, "}")
    writeFile("machine.local.lua", table.concat(lines, "\n") .. "\n")
end

local function hexDecode(s)
    if type(s) ~= "string" or #s % 2 ~= 0 or s:find("[^0-9A-Fa-f]") then
        return nil, "invalid migration code"
    end
    return (s:gsub("..", function(cc)
        return string.char(tonumber(cc, 16))
    end))
end

local function importMigrationCode(code)
    if type(code) ~= "string" or code:sub(1, 4) ~= "IM1-" then
        return false, "unsupported migration code"
    end

    local raw, err = hexDecode(code:sub(5))
    if not raw then return false, err end

    local ok, payload = pcall(textutils.unserializeJSON, raw)
    if not ok or type(payload) ~= "table" or payload.version ~= 1 then
        return false, "invalid migration payload"
    end
    if type(payload.key) ~= "string" or payload.key == "" then
        return false, "migration payload has no machine key"
    end

    writeMachineLocal({
        key = payload.key,
        name = payload.name or payload.key,
        label = payload.label or payload.key,
        role = payload.role,
        network = payload.network or "infra-main",
        networkLabel = payload.networkLabel or "MAIN INFRA",
        modules = payload.modules,
        tags = payload.tags,
    })

    return true, payload
end

local function configureIdentity(preset)
    if fs.exists("machine.local.lua") then
        print("Machine identity: preserved machine.local.lua")
        return
    end

    print("")
    print("Machine identity")
    print("----------------")
    print("1) Create a new persistent logical identity")
    print("2) Import an identity from another computer")
    print("3) Use temporary physical identity cc:" .. tostring(os.getComputerID()))
    write("> ")
    local choice = read()

    if choice == "2" then
        write("Migration code: ")
        local code = read()
        local ok, payload = importMigrationCode(code)
        if not ok then error(payload) end
        print("Imported logical machine: " .. tostring(payload.key))
        print("Physical computer is now cc:" .. tostring(os.getComputerID()))
        return
    end

    if choice == "3" then
        print("No persistent logical identity created.")
        print("Run 'machinectl init' later before relying on this machine in production.")
        return
    end

    local defaultKey = "infra:" .. preset .. "-" .. tostring(os.getComputerID())
    local defaultName = preset .. "-" .. tostring(os.getComputerID())
    local defaultLabel = string.upper(preset) .. " #" .. tostring(os.getComputerID())
    local defaultNetwork = "infra-main"
    local defaultNetworkLabel = "MAIN INFRA"

    write("Machine key [" .. defaultKey .. "]: ")
    local key = read()
    if key == "" then key = defaultKey end

    write("Name [" .. defaultName .. "]: ")
    local name = read()
    if name == "" then name = defaultName end

    write("Label [" .. defaultLabel .. "]: ")
    local label = read()
    if label == "" then label = defaultLabel end

    write("Network [" .. defaultNetwork .. "]: ")
    local network = read()
    if network == "" then network = defaultNetwork end

    write("Network label [" .. defaultNetworkLabel .. "]: ")
    local networkLabel = read()
    if networkLabel == "" then networkLabel = defaultNetworkLabel end

    writeMachineLocal({
        key = key,
        name = name,
        label = label,
        role = preset,
        network = network,
        networkLabel = networkLabel,
    })

    print("Persistent machine identity created: " .. key)
end

local function configureProfile(preset)
    if fs.exists("profile.local.lua") then
        print("Runtime profile: preserved profile.local.lua")
        return
    end

    print("")
    print("Runtime profile")
    print("---------------")
    write("Configure preset package " .. tostring(preset) .. " now? [Y/n] ")
    local answer = read()
    if answer == "" or answer:lower() == "y" or answer:lower() == "yes" then
        shell.run("profilectl.lua", "init")
    else
        print("Preset defaults will be used. Run 'profilectl init' later.")
    end
end

if not http then
    error("HTTP API unavailable. Enable HTTP in CC:Tweaked configuration.")
end

term.clear()
term.setCursorPos(1, 1)
print("CC Infrastructure installer")
print("===========================")

local preset = choosePreset()
print("")
print("Public repository: no GitHub token is required.")
print("Leave token blank (recommended).")
print("Only enter a fine-grained READ token if the repository is private.")
write("Token [blank]: ")
local token = read("*")

print("")
print("Installing runtime preset package: " .. preset)

for _, rel in ipairs(presets[preset]) do
    local source = "cc/" .. preset .. "/" .. rel
    write("- " .. rel .. " ... ")
    local body, err = fetchFile(source, token)
    if not body then
        print("FAILED")
        error(err)
    end
    writeFile(rel, body)
    print("OK")
end

configureIdentity(preset)
configureProfile(preset)

local versionBody = fetchFile("version.json", token)
local installedVersion = nil
if versionBody then
    writeFile(".infra/version.json", versionBody)

    -- Remove the old project-specific metadata after a successful migration.
    if fs.exists(".steamplant-version.json") then
        fs.delete(".steamplant-version.json")
    end

    local ok, parsed = pcall(textutils.unserializeJSON, versionBody)
    if ok and type(parsed) == "table" then
        installedVersion = parsed.version
    end
end

print("")
print("Installation complete.")
print("Preset package: " .. preset)
if installedVersion then
    print("Package: " .. tostring(installedVersion))
end
print("Machine: run 'machinectl status' to verify identity.")
print("Profile: run 'profilectl status' to verify runtime modules/display.")
print("Services: run 'systemctl list' for live runtime state and logs.")
print("Migration: 'machinectl export' on old, then 'machinectl import' on replacement.")
print("Run: reboot")
