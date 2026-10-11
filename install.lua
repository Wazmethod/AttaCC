-- CC Infrastructure installer/updater
-- Bootstrap only: package contents are declared in packages/manifest.lua.

local OWNER = "Wazmethod"
local REPO = "steamplant-cc"
local REF = "dev"

local PRESET_FILE = ".infra/install-preset"
local MACHINE_FILE = ".infra/config/machine.lua"
local PROFILE_FILE = ".infra/config/profile.lua"
local LEGACY_MACHINE_FILE = "machine.local.lua"
local LEGACY_PROFILE_FILE = "profile.local.lua"

local presetPackages = {
    collector = "preset.infrastructure-node",
    controller = "preset.automation-node",
    master = "preset.supervisor",
    pocket = "preset.portable-client",
}

local idDefaults = {
    [0] = "collector",
    [1] = "master",
    [2] = "pocket",
}

local function ensureParent(path)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
end

local function migrateLocalConfig()
    for legacy, target in pairs({
        [LEGACY_MACHINE_FILE] = MACHINE_FILE,
        [LEGACY_PROFILE_FILE] = PROFILE_FILE,
    }) do
        if fs.exists(legacy) and not fs.exists(target) then
            local dir = fs.getDir(target)
            if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
            fs.move(legacy, target)
        end
    end
end

local function writeFile(path, content)
    ensureParent(path)
    local tmp = path .. ".new"
    local h = fs.open(tmp, "w")
    if not h then error("Cannot open " .. tmp) end
    h.write(content)
    h.close()
    if fs.exists(path) then fs.delete(path) end
    fs.move(tmp, path)
end

local function readFile(path)
    if not fs.exists(path) then return nil end
    local h = fs.open(path, "r")
    if not h then return nil end
    local value = h.readAll()
    h.close()
    return value
end

local function headers(token)
    if not token or token == "" then return nil end
    return {
        ["Accept"] = "application/vnd.github.raw+json",
        ["X-GitHub-Api-Version"] = "2022-11-28",
        ["User-Agent"] = "CC-Tweaked-Infra",
        ["Authorization"] = "Bearer " .. token,
    }
end

local function fetchFile(repoPath, token)
    local url
    local requestHeaders = headers(token)

    if requestHeaders then
        url = "https://api.github.com/repos/" .. OWNER .. "/" .. REPO
            .. "/contents/" .. repoPath .. "?ref=" .. REF
    else
        url = "https://raw.githubusercontent.com/" .. OWNER .. "/" .. REPO
            .. "/" .. REF .. "/" .. repoPath
            .. "?cb=" .. tostring(os.epoch("utc"))
    end

    local response, err = http.get(url, requestHeaders)
    if not response then return nil, err or "HTTP request failed" end
    local code = response.getResponseCode()
    local body = response.readAll()
    response.close()
    if code < 200 or code >= 300 then
        return nil, "GitHub HTTP " .. tostring(code) .. " for " .. repoPath
    end
    return body
end

local function choosePreset()
    local saved = readFile(PRESET_FILE)
    if saved then
        saved = saved:gsub("%s+$", "")
        if presetPackages[saved] then
            print("Installed preset: " .. saved)
            return saved
        end
    end

    local default = idDefaults[os.getComputerID()]
    print("Computer ID: " .. tostring(os.getComputerID()))
    if default then
        print("Preset suggested: " .. default)
        write("Use this preset? [Y/n] ")
        local answer = read()
        if answer == "" or answer:lower() == "y" or answer:lower() == "yes" then
            return default
        end
    end

    print("Select installation preset:")
    print("  1) collector   -> infrastructure-node")
    print("  2) master      -> supervisor")
    print("  3) pocket      -> portable-client")
    print("  4) controller  -> automation-node")
    write("> ")
    local answer = read()
    if answer == "1" then return "collector" end
    if answer == "2" then return "master" end
    if answer == "3" then return "pocket" end
    if answer == "4" then return "controller" end
    error("Invalid preset")
end

local function luaQuote(value)
    return string.format("%q", tostring(value or ""))
end

local function writeMachineLocal(value)
    local lines = {
        "return {",
        "    key = " .. luaQuote(value.key) .. ",",
        "    hostname = " .. luaQuote(value.hostname or value.name) .. ",",
        "    label = " .. luaQuote(value.label) .. ",",
        "    network = " .. luaQuote(value.network) .. ",",
        "    networkLabel = " .. luaQuote(value.networkLabel) .. ",",
    }
    if value.role then table.insert(lines, "    role = " .. luaQuote(value.role) .. ",") end
    if type(value.modules) == "table" then
        table.insert(lines, "    modules = {")
        for _, name in ipairs(value.modules) do table.insert(lines, "        " .. luaQuote(name) .. ",") end
        table.insert(lines, "    },")
    end
    if type(value.tags) == "table" then
        table.insert(lines, "    tags = {")
        for _, tag in ipairs(value.tags) do table.insert(lines, "        " .. luaQuote(tag) .. ",") end
        table.insert(lines, "    },")
    end
    table.insert(lines, "}")
    writeFile(MACHINE_FILE, table.concat(lines, "\n") .. "\n")
end

local function hexDecode(s)
    if type(s) ~= "string" or #s % 2 ~= 0 or s:find("[^0-9A-Fa-f]") then
        return nil, "invalid migration code"
    end
    return (s:gsub("..", function(cc) return string.char(tonumber(cc, 16)) end))
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
        hostname = payload.hostname or payload.name or payload.key,
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
    if fs.exists(MACHINE_FILE) then
        print("Machine identity: preserved " .. MACHINE_FILE)
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
        local ok, payload = importMigrationCode(read())
        if not ok then error(payload) end
        print("Imported logical machine: " .. tostring(payload.key))
        return
    elseif choice == "3" then
        print("Temporary physical identity kept.")
        return
    end

    local defaultKey = "infra:" .. preset .. "-" .. tostring(os.getComputerID())
    local defaultHostname = preset .. "-" .. tostring(os.getComputerID())
    local defaultLabel = string.upper(preset) .. " #" .. tostring(os.getComputerID())

    write("Machine key [" .. defaultKey .. "]: ")
    local key = read()
    if key == "" then key = defaultKey end
    write("Hostname [" .. defaultHostname .. "]: ")
    local hostname = read()
    if hostname == "" then hostname = defaultHostname end
    write("Label [" .. defaultLabel .. "]: ")
    local label = read()
    if label == "" then label = defaultLabel end
    write("Network [infra-main]: ")
    local network = read()
    if network == "" then network = "infra-main" end
    write("Network label [MAIN INFRA]: ")
    local networkLabel = read()
    if networkLabel == "" then networkLabel = "MAIN INFRA" end

    writeMachineLocal({
        key = key,
        hostname = hostname,
        label = label,
        role = preset,
        network = network,
        networkLabel = networkLabel,
    })
end

local function configureProfile(preset)
    if fs.exists(PROFILE_FILE) then
        print("Runtime profile: preserved " .. PROFILE_FILE)
        return
    end
    write("Configure " .. preset .. " profile now? [Y/n] ")
    local answer = read()
    if answer == "" or answer:lower() == "y" or answer:lower() == "yes" then
        shell.run("profilectl.lua", "init")
    else
        print("Preset defaults will be used. Run 'profilectl init' later.")
    end
end

if not http then error("HTTP API unavailable. Enable HTTP in CC:Tweaked.") end

term.clear()
term.setCursorPos(1, 1)
print("CC Infrastructure installer")
print("===========================")

migrateLocalConfig()

local preset = choosePreset()
local packageName = presetPackages[preset]
print("Preset package: " .. packageName)

print("")
print("Public repository: leave token blank.")
write("GitHub token [blank]: ")
local token = read("*")

write("- bootstrap pkgctl.lua ... ")
local pkgctl, pkgErr = fetchFile("pkgctl.lua", token)
if not pkgctl then
    print("FAILED")
    error(pkgErr)
end
writeFile("pkgctl.lua", pkgctl)
print("OK")

local command = { "pkgctl.lua", "install", packageName }
if token and token ~= "" then
    table.insert(command, "--token")
    table.insert(command, token)
end

local ok = shell.run(table.unpack(command))
if not ok then error("Package installation failed") end

writeFile(PRESET_FILE, preset .. "\n")
configureIdentity(preset)
configureProfile(preset)

local versionBody = fetchFile("version.json", token)
if versionBody then writeFile(".infra/version.json", versionBody) end

print("")
print("Installation complete.")
print("Preset: " .. preset)
print("Root package: " .. packageName)
print("Packages: pkgctl status")
print("Update later: install   OR   pkgctl update")
print("Storage: storagectl ping")
print("Run: reboot")
