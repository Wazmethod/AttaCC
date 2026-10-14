-- AttaCC installer/updater
-- Bootstrap only: package contents are declared in packages/manifest.lua.

local OWNER = "Wazmethod"
local REPO = "steamplant-cc"
local REF = "dev"
local SOURCE_FILE = "/etc/pkgctl/source.lua"
local function configuredSource()
    if not fs.exists(SOURCE_FILE) then return nil end
    local ok,v=pcall(dofile,SOURCE_FILE)
    return ok and type(v)=="table" and v.url or nil
end
local SOURCE = configuredSource()

local PRESET_FILE = "/etc/preset"
local MACHINE_FILE = "/etc/machine.lua"
local PROFILE_FILE = "/etc/profile.lua"

local presetPackages = {
    steamplant = "preset.steamplant",
    master = "preset.master",
    pocket = "preset.pocket",
    workstation = "preset.workstation",
    dashboard = "preset.dashboard",
}

local idDefaults = {
    [0] = "steamplant",
    [1] = "master",
    [2] = "pocket",
}

local function ensureParent(path)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
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
        ["User-Agent"] = "AttaCC",
        ["Authorization"] = "Bearer " .. token,
    }
end

local function fetchFile(repoPath, token)
    local url
    local requestHeaders = headers(token)

    if SOURCE then
        url = SOURCE:gsub("/+$","") .. "/" .. repoPath .. "?cb=" .. tostring(os.epoch("utc"))
        requestHeaders = nil
    elseif requestHeaders then
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
        return nil, "Repository HTTP " .. tostring(code) .. " for " .. repoPath
    end
    return body
end

local customPresetPrograms = {}
local function discoverPresets(token)
    local body, err = fetchFile("packages/manifest.lua", token)
    if not body then
        print("Preset discovery: " .. tostring(err) .. "; using built-in presets")
        return
    end
    local fn = load(body, "@package-manifest", "t", {})
    if not fn then print("Preset manifest invalid; using built-ins") return end
    local ok, manifest = pcall(fn)
    if not ok or type(manifest) ~= "table" or type(manifest.packages) ~= "table" then
        print("Preset manifest unavailable; using built-ins")
        return
    end
    for name, def in pairs(manifest.packages) do
        local short = type(name) == "string" and name:match("^preset%.([%w_-]+)$")
        if short and type(def)=="table" and def.kind=="preset"
            and type(def.program)=="string" and def.program:match("^[%w_./-]+$")
            and not presetPackages[short] then
            presetPackages[short] = name
            customPresetPrograms[short] = def.program
        end
    end
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
    local choices = { "steamplant", "master", "pocket", "workstation", "dashboard" }
    local extra = {}
    for name in pairs(customPresetPrograms) do extra[#extra + 1] = name end
    table.sort(extra)
    for _, name in ipairs(extra) do choices[#choices + 1] = name end
    for index, name in ipairs(choices) do print("  " .. index .. ") " .. name) end
    write("> ")
    local index = tonumber(read())
    if index and choices[index] then return choices[index] end
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
    }
    if value.role then table.insert(lines, "    role = " .. luaQuote(value.role) .. ",") end
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
        tags = payload.tags,
    })
    return true, payload
end

local function configureIdentity(preset)
    if fs.exists(MACHINE_FILE) then
        local ok, current = pcall(dofile, MACHINE_FILE)
        if not ok or type(current) ~= "table" then
            error("Invalid " .. MACHINE_FILE)
        end
        current.role = preset
        writeMachineLocal(current)
        print("Machine identity: preserved; role set to " .. tostring(preset))
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
    writeMachineLocal({
        key = key,
        hostname = hostname,
        label = label,
        role = preset,
        network = network,
    })
end

local function configureProfile(preset)
    if fs.exists(PROFILE_FILE) or fs.exists("/etc/apps.lua") or fs.exists("/etc/io.lua") then
        print("Machine configuration: preserved existing profile/apps/io files")
        return
    end
    write("Configure " .. preset .. " profile now? [Y/n] ")
    local answer = read()
    if answer == "" or answer:lower() == "y" or answer:lower() == "yes" then
        shell.run("profilectl.lua", "config", "inter")
    else
        print("Preset defaults will be used. Run 'profilectl config inter' later.")
    end
end

if not http then error("HTTP API unavailable. Enable HTTP in CC:Tweaked.") end

local args = { ... }
local token = nil
for n = 1, #args do
    if args[n] == "--source" and args[n+1] then
        SOURCE = args[n+1]:gsub("/+$","")
        if not SOURCE:match("^https?://[^%s]+/repo$") then error("Invalid --source URL; expected https://host/repo") end
    end
    if args[n] == "--token" and args[n + 1] then
        token = args[n + 1]
    end
end

term.clear()
term.setCursorPos(1, 1)
print("AttaCC installer")
print("================")


discoverPresets(token)
local preset = choosePreset()
local packageName = presetPackages[preset]
print("Preset package: " .. packageName)

print("")
if token and token ~= "" then
    print("GitHub authentication: token supplied")
else
    print("GitHub authentication: public repository")
end

write("- bootstrap pkgctl.lua ... ")
local pkgctl, pkgErr = fetchFile("pkgctl.lua", token)
if not pkgctl then
    print("FAILED")
    error(pkgErr)
end
writeFile("pkgctl.lua", pkgctl)
if SOURCE then
    ensureParent(SOURCE_FILE)
    writeFile(SOURCE_FILE,"return { url = "..string.format("%q",SOURCE).." }\n")
end
print("OK")

local command = { "pkgctl.lua", "install", packageName }
if token and token ~= "" then
    table.insert(command, "--token")
    table.insert(command, token)
end

local ok = shell.run(table.unpack(command))
if not ok then error("Package installation failed") end


if customPresetPrograms[preset] then
    local activated = shell.run("pkgctl.lua", "activate", packageName)
    if not activated then error("Custom preset activation failed") end
else
    writeFile(PRESET_FILE, preset .. "\n")
end
configureIdentity(preset)
configureProfile(preset)
if preset == "master" then
    print("")
    print("WEBBRIDGE (optional): publish AttaCC to the Web dashboard.")
    print("Start the Web backend and configure its MACHINE_TOKEN first.")
    print("Run 'webbridgectl configure' to set the WebSocket URL and machine token.")
    print("WebBridge starts automatically after reboot when configured.")
    write("Configure WebBridge now? [y/N] ")
    local choice=read():lower()
    if choice=="y" or choice=="yes" then
        local webOk=shell.run("webbridgectl.lua","configure")
        if not webOk then print("WebBridge setup incomplete; run webbridgectl configure later.") end
    end
end

local versionBody = fetchFile("version.json", token)
if versionBody then writeFile("/var/lib/pkgctl/version.json", versionBody) end

settings.set("motd.enable", false)
pcall(settings.save)

print("")
print("Installation complete.")
print("Preset: " .. preset)
print("Root package: " .. packageName)
print("Packages: pkgctl status")
print("Update later: install   OR   pkgctl update")
print("Storage: storagectl ping")
print("Run: reboot")
