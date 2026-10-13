-- CC Infrastructure package manager
local OWNER = "Wazmethod"
local REPO = "steamplant-cc"
local REF = "dev"

local DB_FILE = "/var/lib/pkgctl/packages.json"
local LEGACY_DB_FILES = {
    "/var/lib/infra/packages.json",
    ".infra/packages.json",
}
local MANIFEST_PATH = "packages/manifest.lua"

local args = { ... }
local token = nil
local noConfig = false

for i = #args, 1, -1 do
    if args[i] == "--no-config" then
        noConfig = true
        table.remove(args, i)
    end
end

if not fs.exists(DB_FILE) then
    for _, legacy in ipairs(LEGACY_DB_FILES) do
        if fs.exists(legacy) then
            local dir = fs.getDir(DB_FILE)
            if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
            fs.move(legacy, DB_FILE)
            break
        end
    end
end

for i = #args, 1, -1 do
    if args[i] == "--token" and args[i + 1] then
        token = args[i + 1]
        table.remove(args, i + 1)
        table.remove(args, i)
    end
end

local function ensureParent(path)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
end

local function writeFile(path, content)
    ensureParent(path)
    local tmp = path .. ".new"
    local h = fs.open(tmp, "w")
    if not h then return false, "cannot open " .. tmp end
    h.write(content)
    h.close()
    if fs.exists(path) then fs.delete(path) end
    fs.move(tmp, path)
    return true
end

local function readJson(path, fallback)
    if not fs.exists(path) then return fallback end
    local h = fs.open(path, "r")
    if not h then return fallback end
    local raw = h.readAll()
    h.close()
    local ok, value = pcall(textutils.unserializeJSON, raw)
    if ok and type(value) == "table" then return value end
    return fallback
end

local function writeJson(path, value)
    local ok, raw = pcall(textutils.serializeJSON, value)
    if not ok or not raw then return false, "json serialization failed" end
    return writeFile(path, raw)
end

local function headers()
    if not token or token == "" then return nil end
    return {
        ["Accept"] = "application/vnd.github.raw+json",
        ["X-GitHub-Api-Version"] = "2022-11-28",
        ["User-Agent"] = "CC-Tweaked-Infra",
        ["Authorization"] = "Bearer " .. token,
    }
end

local function fetch(repoPath)
    if not http then return nil, "HTTP API unavailable" end

    local url
    local h = headers()
    if h then
        url = "https://api.github.com/repos/" .. OWNER .. "/" .. REPO
            .. "/contents/" .. repoPath .. "?ref=" .. REF
    else
        url = "https://raw.githubusercontent.com/" .. OWNER .. "/" .. REPO
            .. "/" .. REF .. "/" .. repoPath
            .. "?cb=" .. tostring(os.epoch("utc"))
    end

    local response, err = http.get(url, h)
    if not response then return nil, err or "HTTP request failed" end
    local code = response.getResponseCode()
    local body = response.readAll()
    response.close()

    if code < 200 or code >= 300 then
        return nil, "HTTP " .. tostring(code) .. " for " .. repoPath
    end
    return body
end

local function loadManifest()
    local body, err = fetch(MANIFEST_PATH)
    if not body then return nil, err end

    local fn, loadErr = load(body, "@package-manifest", "t", {})
    if not fn then return nil, loadErr end

    local ok, manifest = pcall(fn)
    if not ok or type(manifest) ~= "table" or type(manifest.packages) ~= "table" then
        return nil, "invalid package manifest"
    end
    return manifest
end

local function db()
    local data = readJson(DB_FILE, {
        format = 1,
        installed = {},
        updatedAt = 0,
    })
    data.installed = type(data.installed) == "table" and data.installed or {}
    return data
end

local function resolveName(manifest, name)
    return (manifest.aliases and manifest.aliases[name]) or name
end

local function resolve(manifest, name, ordered, visiting, seen)
    name = resolveName(manifest, name)
    local def = manifest.packages[name]
    if not def then return false, "unknown package: " .. tostring(name) end

    visiting = visiting or {}
    seen = seen or {}
    ordered = ordered or {}

    if seen[name] then return true, ordered end
    if visiting[name] then return false, "dependency cycle at " .. name end
    visiting[name] = true

    for _, dep in ipairs(def.depends or {}) do
        local ok, err = resolve(manifest, dep, ordered, visiting, seen)
        if not ok then return false, err end
    end

    visiting[name] = nil
    seen[name] = true
    table.insert(ordered, name)
    return true, ordered
end

local function ownedByAnotherPackage(state, packageName, path)
    for otherName, meta in pairs(state.installed or {}) do
        if otherName ~= packageName then
            for _, owned in ipairs(meta.files or {}) do
                if owned == path then return true end
            end
        end
    end
    return false
end

local function installOne(manifest, name, state, explicit)
    local def = manifest.packages[name]
    print("")
    print("[" .. tostring(def.kind or "package") .. "] " .. name)

    local installedFiles = {}
    for _, file in ipairs(def.files or {}) do
        local src = type(file) == "table" and file.src or file
        local dest = type(file) == "table" and (file.dest or file.src) or file
        write("  " .. dest .. " ... ")
        local body, err = fetch(src)
        if not body then
            print("FAILED")
            return false, err
        end
        local ok, writeErr = writeFile(dest, body)
        if not ok then
            print("FAILED")
            return false, writeErr
        end
        table.insert(installedFiles, dest)
        print("OK")
    end

    local previous = state.installed[name]

    if previous and type(previous.files) == "table" then
        local current = {}
        for _, path in ipairs(installedFiles) do current[path] = true end
        for _, oldPath in ipairs(previous.files) do
            if not current[oldPath]
                and fs.exists(oldPath)
                and not ownedByAnotherPackage(state, name, oldPath)
            then
                fs.delete(oldPath)
                print("  removed obsolete " .. oldPath)
            end
        end
    end

    state.installed[name] = {
        kind = def.kind,
        version = manifest.version,
        explicit = explicit == true or (previous and previous.explicit == true) or false,
        installedAt = os.epoch("utc"),
        configurable = type(def.configure) == "table" and def.configure.program ~= nil,
        files = installedFiles,
    }
    state.updatedAt = os.epoch("utc")
    writeJson(DB_FILE, state)
    return true, nil, previous == nil
end

local function installPackage(manifest, requested)
    requested = resolveName(manifest, requested)
    local ok, ordered = resolve(manifest, requested)
    if not ok then return false, ordered end

    local state = db()
    local firstInstall = {}
    for _, name in ipairs(ordered) do
        local oneOk, err, fresh = installOne(manifest, name, state, name == requested)
        if not oneOk then return false, err end
        if fresh then table.insert(firstInstall, name) end
    end
    return true, firstInstall
end

local function updateInstalled(manifest, only)
    local state = db()
    local roots = {}

    if only then
        table.insert(roots, resolveName(manifest, only))
    else
        for name, meta in pairs(state.installed) do
            if meta.explicit == true then table.insert(roots, name) end
        end
        table.sort(roots)
    end

    if #roots == 0 then
        return false, "no explicit packages installed"
    end

    for _, name in ipairs(roots) do
        local ok, result = installPackage(manifest, name)
        if not ok then return false, result end
    end
    return true
end

local function printList(manifest)
    local names = {}
    for name in pairs(manifest.packages) do table.insert(names, name) end
    table.sort(names)
    for _, name in ipairs(names) do
        local def = manifest.packages[name]
        print(string.format("%-32s %-8s %s", name, def.kind or "", def.description or ""))
    end
end

local function printPackage(manifest, requested)
    local name = resolveName(manifest, requested)
    local def = manifest.packages[name]
    if not def then error("unknown package: " .. tostring(name)) end

    local ok, ordered = resolve(manifest, name)
    if not ok then error(ordered) end

    print("Package      : " .. tostring(name))
    print("Kind         : " .. tostring(def.kind or "package"))
    print("Description  : " .. tostring(def.description or "-"))
    print("Dependencies : " .. (#(def.depends or {}) > 0 and table.concat(def.depends, ", ") or "-"))
    print("Configurator : " .. tostring(def.configure and def.configure.program or "-"))
    print("Closure      : " .. table.concat(ordered, " -> "))

    local state = db()
    local meta = state.installed[name]
    print("Installed    : " .. tostring(meta ~= nil))
    if meta then
        print("Explicit     : " .. tostring(meta.explicit == true))
        print("Version      : " .. tostring(meta.version or "?"))
    end
end

local function printStatus(manifest)
    local state = db()
    local names = {}
    for name in pairs(state.installed) do table.insert(names, name) end
    table.sort(names)

    if #names == 0 then
        print("No packages installed.")
        return
    end

    for _, name in ipairs(names) do
        local meta = state.installed[name]
        local missing = 0
        for _, path in ipairs(meta.files or {}) do
            if not fs.exists(path) then missing = missing + 1 end
        end
        local marker = meta.explicit and "*" or " "
        local stateText = missing == 0 and "OK" or ("MISSING:" .. tostring(missing))
        print(string.format("%s %-31s %-14s %s", marker, name, meta.version or "?", stateText))
    end
    print("* explicitly installed root package")
end

local function applyShellSettings()
    if fs.exists("startup/infra-completion.lua") or fs.exists("less.lua") then
        settings.set("motd.enable", false)
        pcall(settings.save)
    end
end

local function configurePackage(manifest, requested)
    local name = resolveName(manifest, requested)
    local def = manifest.packages[name]
    if not def then return false, "unknown package: " .. tostring(name) end
    local cfg = def.configure
    if type(cfg) ~= "table" or not cfg.program then
        print("No first-run configuration for " .. tostring(name) .. ".")
        return true
    end

    local command = { cfg.program }
    for _, value in ipairs(cfg.args or {}) do table.insert(command, tostring(value)) end

    print("")
    print("Configuring " .. tostring(name) .. " ...")
    local ok = shell.run(table.unpack(command))
    if not ok then return false, "configuration failed for " .. tostring(name) end
    return true
end

local function runMigrations()
    if not fs.exists("migrate.lua") then return true end
    local ok = shell.run("migrate.lua", "--quiet")
    if not ok then return false, "filesystem migration failed" end
    return true
end

local function usage()
    print("pkgctl list")
    print("pkgctl status")
    print("pkgctl show <package>")
    print("pkgctl install <package>")
    print("pkgctl update [package]")
    print("pkgctl configure <package>")
    print("")
    print("Examples:")
    print("  pkgctl install module.steamplant")
    print("  pkgctl install service.shared-storage-client")
    print("  pkgctl install service.display")
    print("  pkgctl configure service.display")
    print("  pkgctl update")
end

local command = args[1]
if not command or command == "help" or command == "--help" then
    usage()
    return
end

local manifest, err = loadManifest()
if not manifest then error("Cannot load package manifest: " .. tostring(err)) end

if command == "list" then
    printList(manifest)
elseif command == "show" or command == "deps" then
    if not args[2] then error("package name required") end
    printPackage(manifest, args[2])
elseif command == "status" then
    printStatus(manifest)
elseif command == "install" then
    if not args[2] then error("package name required") end
    local ok, installResult = installPackage(manifest, args[2])
    if not ok then error(installResult) end
    applyShellSettings()
    if not noConfig then
        for _, packageName in ipairs(installResult or {}) do
            local def = manifest.packages[packageName]
            if def and def.configure then
                local cfgOk, cfgErr = configurePackage(manifest, packageName)
                if not cfgOk then error(cfgErr) end
            end
        end
    end
    print("")
    local migrateOk, migrateErr = runMigrations()
    if not migrateOk then error(migrateErr) end
    print("Package installation complete.")
elseif command == "configure" then
    if not args[2] then error("package name required") end
    local ok, cfgErr = configurePackage(manifest, args[2])
    if not ok then error(cfgErr) end
elseif command == "update" or command == "upgrade" then
    local ok, updateErr = updateInstalled(manifest, args[2])
    if not ok then error(updateErr) end
    applyShellSettings()
    local migrateOk, migrateErr = runMigrations()
    if not migrateOk then error(migrateErr) end
    print("")
    print("Package update complete.")
else
    usage()
    error("unknown command: " .. tostring(command))
end
