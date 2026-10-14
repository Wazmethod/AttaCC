-- AttaCC package manager
local OWNER = "Wazmethod"
local REPO = "steamplant-cc"
local REF = "dev"
local SOURCE_FILE = "/etc/pkgctl/source.lua"
local function sourceUrl()
    if fs.exists(SOURCE_FILE) then
        local ok,v=pcall(dofile,SOURCE_FILE)
        if ok and type(v)=="table" and type(v.url)=="string" then return v.url:gsub("/+$","") end
    end
    return nil
end
local function saveSource(url)
    if not fs.exists("/etc/pkgctl") then fs.makeDir("/etc/pkgctl") end
    local h=fs.open(SOURCE_FILE..".new","w")
    if not h then return false,"unable to write source" end
    h.write("return { url = "..string.format("%q",url).." }\n") h.close()
    if fs.exists(SOURCE_FILE) then fs.delete(SOURCE_FILE) end
    fs.move(SOURCE_FILE..".new",SOURCE_FILE)
    return true
end

local DB_FILE = "/var/lib/pkgctl/packages.json"
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
        ["User-Agent"] = "AttaCC",
        ["Authorization"] = "Bearer " .. token,
    }
end

local function fetch(repoPath)
    if not http then return nil, "HTTP API unavailable" end

    local url
    local h = headers()
    local base = sourceUrl()
    if base then
        url = base .. "/" .. repoPath .. "?cb=" .. tostring(os.epoch("utc"))
        h = nil
    elseif h then
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

local function packageVersion(manifest, name)
    local def = manifest.packages[name] or {}
    return tostring(def.version or manifest.version or "unknown")
end

-- Download the entire package before touching any installed file.
-- Roll back changed destinations if a write fails (CraftOS has no atomic directory swap).
local function installOne(manifest, name, state, explicit)
    local def = manifest.packages[name]
    print("")
    print("[" .. tostring(def.kind or "package") .. "] " .. name .. " (" .. packageVersion(manifest,name) .. ")")

    local incoming, paths, present = {}, {}, {}
    for _, file in ipairs(def.files or {}) do
        local src = type(file) == "table" and file.src or file
        local dest = type(file) == "table" and (file.dest or file.src) or file
        if type(src) ~= "string" or type(dest) ~= "string"
            or src:sub(1, 1) == "/" or dest:sub(1, 1) == "/"
            or src:find("\\\\") or dest:find("\\\\")
            or src:find("..", 1, true) or dest:find("..", 1, true)
            or src == "" or dest == ""
            or (dest == "startup.lua" and name ~= "core.runtime")
            or dest == "pkgctl.lua.new"
            or dest:match("^etc/") or dest:match("^/etc/") then
            return false, "invalid or protected destination for " .. tostring(name)
        end
        if present[dest] then return false, "duplicate destination " .. dest end
        present[dest] = true
        write("  downloading " .. tostring(src) .. " ... ")
        local body, err = fetch(src)
        if not body then print("FAILED") return false, err end
        incoming[#incoming + 1] = { dest = dest, body = body }
        paths[#paths + 1] = dest
        print("OK")
    end

    local previous = state.installed[name]
    local oldContents, changed = {}, {}
    local obsolete = {}
    if previous and type(previous.files) == "table" then
        for _, oldPath in ipairs(previous.files) do
            if not present[oldPath] and fs.exists(oldPath)
                and not ownedByAnotherPackage(state, name, oldPath) then
                obsolete[#obsolete + 1] = oldPath
            end
        end
    end

    for _, file in ipairs(incoming) do
        if fs.exists(file.dest) then
            if fs.isDir(file.dest) then return false, "destination is directory: " .. file.dest end
            local h = fs.open(file.dest, "r")
            if not h then return false, "cannot back up " .. file.dest end
            oldContents[file.dest] = { existed = true, body = h.readAll() }
            h.close()
        else oldContents[file.dest] = { existed = false } end
    end
    for _, oldPath in ipairs(obsolete) do
        local h = fs.open(oldPath, "r")
        if not h then return false, "cannot back up obsolete " .. oldPath end
        oldContents[oldPath] = { existed = true, body = h.readAll() }
        h.close()
    end

    local function restore()
        for i = #changed, 1, -1 do
            local path = changed[i]
            local old = oldContents[path]
            if old and old.existed then
                local ok = writeFile(path, old.body)
                if not ok then printError("manual restore required: " .. path) end
            elseif fs.exists(path) then fs.delete(path) end
        end
    end

    for _, file in ipairs(incoming) do
        changed[#changed + 1] = file.dest
        local ok, err = writeFile(file.dest, file.body)
        if not ok then restore() return false, "write failed: " .. tostring(err) end
    end
    for _, oldPath in ipairs(obsolete) do
        changed[#changed + 1] = oldPath
        fs.delete(oldPath)
        print("  removed obsolete " .. oldPath)
    end

    local oldMeta = state.installed[name]
    state.installed[name] = {
        kind = def.kind,
        version = packageVersion(manifest, name),
        explicit = explicit == true or (previous and previous.explicit == true) or false,
        installedAt = os.epoch("utc"),
        configurable = type(def.configure) == "table" and def.configure.program ~= nil,
        webConfigurable = type(def.configure) == "table" and def.configure.web == true,
        files = paths,
    }
    state.updatedAt = os.epoch("utc")
    local saved, saveErr = writeJson(DB_FILE, state)
    if not saved then
        restore()
        state.installed[name] = oldMeta
        return false, "package registry update failed: " .. tostring(saveErr)
    end
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
            if meta.explicit == true then
                local resolved = resolveName(manifest, name)
                if manifest.packages[resolved] then
                    table.insert(roots, resolved)
                else
                    print("retired package root ignored during update: " .. tostring(name))
                end
            end
        end
        table.sort(roots)
    end

    if #roots == 0 and fs.exists("/etc/preset") then
        local h = fs.open("/etc/preset", "r")
        local preset = h and h.readAll() or nil
        if h then h.close() end
        preset = preset and preset:gsub("%s+$", "") or nil
        local candidate = preset and ("preset." .. tostring(preset)) or nil
        if candidate and manifest.packages[candidate] then
            table.insert(roots, candidate)
            print("using active preset root: " .. candidate)
        end
    end

    if #roots == 0 then
        return false, "no current explicit packages installed"
    end

    for _, name in ipairs(roots) do
        local ok, result = installPackage(manifest, name)
        if not ok then return false, result end
    end
    return true
end

local function prunePackages(manifest)
    local state = db()
    local keep = {}
    local roots = {}

    for name, meta in pairs(state.installed) do
        if meta.explicit == true then
            if manifest.packages[name] then
                table.insert(roots, name)
            else
                print("retired package root will be pruned: " .. tostring(name))
            end
        end
    end
    table.sort(roots)

    if #roots == 0 then
        return false, "no current explicit packages installed; reinstall a preset before pruning"
    end

    for _, root in ipairs(roots) do
        local ok, ordered = resolve(manifest, root)
        if not ok then return false, ordered end
        for _, name in ipairs(ordered) do keep[name] = true end
    end

    local retainedFiles = {}
    for name, meta in pairs(state.installed) do
        if keep[name] then
            for _, path in ipairs(meta.files or {}) do retainedFiles[path] = true end
        end
    end

    local orphans = {}
    for name in pairs(state.installed) do
        if not keep[name] then table.insert(orphans, name) end
    end
    table.sort(orphans)

    local removedFiles = 0
    for _, name in ipairs(orphans) do
        local meta = state.installed[name]
        print("prune " .. tostring(name))
        for _, path in ipairs(meta.files or {}) do
            if not retainedFiles[path] and fs.exists(path) then
                fs.delete(path)
                removedFiles = removedFiles + 1
                print("  removed " .. tostring(path))
            end
        end
        state.installed[name] = nil
    end

    state.updatedAt = os.epoch("utc")
    local ok, err = writeJson(DB_FILE, state)
    if not ok then return false, err end

    print("")
    print(string.format("Pruned %d package(s), removed %d file/path(s).", #orphans, removedFiles))
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
    print("Available    : " .. packageVersion(manifest, name))
    print("Dependencies : " .. (#(def.depends or {}) > 0 and table.concat(def.depends, ", ") or "-"))
    print("Configurator : " .. tostring(def.configure and def.configure.program or "-"))
    print("Closure      : " .. table.concat(ordered, " -> "))

    local state = db()
    local meta = state.installed[name]
    print("Installed    : " .. tostring(meta ~= nil))
    if meta then
        print("Explicit     : " .. tostring(meta.explicit == true))
        print("Installed ver: " .. tostring(meta.version or "?"))
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
        local available = manifest.packages[name] and packageVersion(manifest,name) or "removed"
        local change = tostring(meta.version or "?") ~= available and " -> "..available or ""
        print(string.format("%s %-31s %-14s %s%s", marker, name, meta.version or "?", stateText, change))
    end
    print("* explicitly installed root package")
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

local function activatePreset(manifest, requested)
    local name = resolveName(manifest, requested)
    local def = manifest.packages[name]
    if not def or def.kind ~= "preset" then return false, "not a preset: " .. tostring(name) end
    local preset = name:match("^preset%.([%w_-]+)$")
    if not preset then return false, "invalid preset name" end
    if type(def.program) ~= "string" or def.program == "" then
        return false, "preset lacks program; built-in presets are activated by install"
    end
    if not db().installed[name] then return false, "install the preset first: pkgctl install " .. name end
    if not fs.exists(def.program) then
        return false, "program not installed: " .. def.program .. " (run pkgctl install " .. name .. ")"
    end
    local ok, err = writeFile("/etc/preset_app.lua",
        "return { preset = " .. string.format("%q", preset) ..
        ", program = " .. string.format("%q", def.program) .. " }\n")
    if not ok then return false, err end
    return writeFile("/etc/preset", preset .. "\n")
end

local function usage()
    print("pkgctl list")
    print("pkgctl status")
    print("pkgctl show <package>")
    print("pkgctl install <package>")
    print("pkgctl update [package]")
    print("pkgctl configure <package>")
    print("pkgctl prune")
    print("pkgctl activate preset.<name>    (custom presets)")
    print("pkgctl source show|set <url>|test|github")
    print("")
    print("Examples:")
    print("  pkgctl install app.steamplant")
    print("  pkgctl install module.storage-client")
    print("  pkgctl install module.display")
    print("  pkgctl install preset.master")
    print("  pkgctl update")
    print("  pkgctl prune")
end

local command = args[1]
if not command or command == "help" or command == "--help" then
    usage()
    return
end

if command == "source" then
    local action = args[2] or "show"
    if action == "show" then
        print("Package source: "..tostring(sourceUrl() or "GitHub fallback ("..REF..")"))
    elseif action == "set" then
        local url=args[3]
        if not url or not url:match("^https?://[^%s]+/repo/?$") then
            error("Usage: pkgctl source set https://your-host/repo")
        end
        local ok,err=saveSource(url:gsub("/+$",""))
        if not ok then error(err) end
        print("Source saved: "..url)
    elseif action == "github" then
        if fs.exists(SOURCE_FILE) then fs.delete(SOURCE_FILE) end
        print("Source reset to GitHub fallback")
    elseif action == "test" then
        local manifest,err=loadManifest()
        if not manifest then error("Source failed: "..tostring(err)) end
        print("Repository OK, version "..tostring(manifest.version))
    else error("Unknown source action") end
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
    print("Package installation complete.")
elseif command == "activate" then
    if not args[2] then error("preset name required") end
    local ok, err = activatePreset(manifest,args[2])
    if not ok then error(err) end
    print("Preset activated. Reboot to launch.")
elseif command == "configure" then
    if not args[2] then error("package name required") end
    local ok, cfgErr = configurePackage(manifest, args[2])
    if not ok then error(cfgErr) end
elseif command == "update" or command == "upgrade" then
    local ok, updateErr = updateInstalled(manifest, args[2])
    if not ok then error(updateErr) end
    print("")
    print("Package update complete.")
elseif command == "prune" then
    local ok, pruneErr = prunePackages(manifest)
    if not ok then error(pruneErr) end
else
    usage()
    error("unknown command: " .. tostring(command))
end
