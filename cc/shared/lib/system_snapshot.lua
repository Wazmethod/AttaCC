local services = require("lib.services")
local modules = require("lib.modules")
local runtime = require("lib.runtime")
local paths = require("lib.paths")

local M = {}
local cache = nil
local cacheAt = 0

local function readJson(path)
    if not fs.exists(path) then return nil end
    local h = fs.open(path, "r")
    if not h then return nil end
    local raw = h.readAll()
    h.close()
    local ok, value = pcall(textutils.unserializeJSON, raw)
    if ok and type(value) == "table" then return value end
    return nil
end

local function listServiceModules(serviceName, service)
    local out, seen = {}, {}

    local function add(name)
        name = tostring(name or ""):gsub("%.mod$", "")
        if name ~= "" and not seen[name] then
            seen[name] = true
            table.insert(out, name)
        end
    end

    for _, name in ipairs((service and service.modules) or {}) do add(name) end

    for _, moduleName in ipairs(modules.names()) do
        local def = modules.definition(moduleName)
        for _, requirement in ipairs((def and def.requires) or {}) do
            local serviceReq = tostring(requirement):gsub("%.service$", "")
            if serviceReq == serviceName then add(moduleName) end
        end
    end

    table.sort(out)
    return out
end

local function publicWebDescriptor(web)
    if type(web) ~= "table" or web.visible == false then return nil end
    local out = {
        visible = web.visible ~= false,
        title = web.title,
        section = web.section or "services",
        description = web.description,
        exports = web.exports,
        commands = {},
    }

    for _, command in ipairs(web.commands or {}) do
        if type(command) == "table" and command.id then
            table.insert(out.commands, {
                id = tostring(command.id),
                label = command.label or command.id,
                tone = command.tone,
                confirm = command.confirm == true,
                args = command.argsSchema,
            })
        end
    end

    return out
end

local function exportedData(service, live)
    local web = service and service.web
    if type(web) ~= "table" then return nil end
    local data = live and live.webData
    if type(data) ~= "table" then return nil end

    if type(web.exports) ~= "table" or #web.exports == 0 then
        return data
    end

    local out = {}
    for _, key in ipairs(web.exports) do
        if data[key] ~= nil then out[key] = data[key] end
    end
    return out
end

function M.build(force)
    local now = os.epoch("utc")
    if not force and cache and (now - cacheAt) < 750 then return cache end

    services.syncRuntime()
    modules.syncRuntime()

    local runtimeSnapshot = runtime.snapshot()
    local liveStates = runtimeSnapshot.services or {}

    local serviceList = {}
    local processesByBinary = {}

    for _, name in ipairs(services.names()) do
        local service = services.status(name)
        local live = liveStates["service:" .. name] or {}
        local state = live.status
            or (service.enabled and (service.active and "starting" or "inactive") or "disabled")
        local moduleNames = listServiceModules(name, service)

        local item = {
            name = name,
            unit = name .. ".service",
            description = service.description,
            state = state,
            enabled = service.enabled,
            active = service.active,
            protected = service.protected,
            binary = service.binary,
            pid = live.pid,
            since = live.since,
            updatedAt = live.updatedAt,
            detail = live.detail,
            depends = service.depends or {},
            modules = moduleNames,
            unitPath = service.unitPath,
            configPath = service.configPath,
            web = publicWebDescriptor(service.web),
            data = exportedData(service, live),
        }
        table.insert(serviceList, item)

        if service.binary then
            local process = processesByBinary[service.binary]
            if not process then
                process = {
                    binary = service.binary,
                    name = fs.getName(service.binary):gsub("%.lua$", ""),
                    pid = live.pid,
                    state = state,
                    services = {},
                    modules = {},
                }
                processesByBinary[service.binary] = process
            end
            table.insert(process.services, name)

            local seen = {}
            for _, mod in ipairs(process.modules) do seen[mod] = true end
            for _, mod in ipairs(moduleNames) do
                if not seen[mod] then
                    table.insert(process.modules, mod)
                    seen[mod] = true
                end
            end
            if state == "failed" then process.state = "failed" end
            if live.pid then process.pid = live.pid end
        end
    end

    table.sort(serviceList, function(a,b) return a.name < b.name end)

    local processList = {}
    for _, process in pairs(processesByBinary) do
        table.sort(process.services)
        table.sort(process.modules)
        table.insert(processList, process)
    end
    table.sort(processList, function(a,b) return a.name < b.name end)

    local moduleList = {}
    for _, name in ipairs(modules.names()) do
        local status = modules.status(name)
        table.insert(moduleList, {
            name = name,
            unit = name .. ".mod",
            state = status and status.state or "unknown",
            description = status and status.description or nil,
            detail = status and status.detail or nil,
            requires = status and status.requires or {},
            missing = status and status.missing or {},
        })
    end
    table.sort(moduleList, function(a,b) return a.name < b.name end)

    local version = readJson(paths.version)
    local packageDb = readJson(paths.packages) or { installed = {} }
    local packages = {}
    for name, meta in pairs(packageDb.installed or {}) do
        table.insert(packages, {
            name = name,
            kind = meta.kind,
            version = meta.version,
            explicit = meta.explicit == true,
            configurable = meta.configurable == true,
            webConfigurable = meta.webConfigurable == true,
            installedAt = meta.installedAt,
        })
    end
    table.sort(packages, function(a,b) return a.name < b.name end)

    cache = {
        generatedAt = now,
        schema = readJson(paths.schema),
        version = version,
        services = serviceList,
        processes = processList,
        modules = moduleList,
        packages = packages,
    }
    cacheAt = now
    return cache
end

return M
