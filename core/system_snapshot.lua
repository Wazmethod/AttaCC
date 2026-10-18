local runtime = require("lib.runtime")
local paths = require("lib.paths")

local M = {}
local cache
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

local function packageList()
    local packageDb = readJson(paths.packages) or { installed = {} }
    local out = {}
    for name, meta in pairs(packageDb.installed or {}) do
        table.insert(out, {
            name = name,
            kind = meta.kind,
            version = meta.version,
            explicit = meta.explicit == true,
            configurable = meta.configurable == true,
            webConfigurable = meta.webConfigurable == true,
            installedAt = meta.installedAt,
        })
    end
    table.sort(out, function(a,b) return a.name < b.name end)
    return out
end

local function runtimeLists()
    local snap = runtime.snapshot()
    local entries = snap.entries or {}
    local apps, modules, capabilities = {}, {}, {}

    for name, entry in pairs(entries) do
        local bucket, short
        short = name:match("^app:(.+)$")
        if short then bucket = apps end
        if not bucket then
            short = name:match("^module:(.+)$")
            if short then bucket = modules end
        end
        if not bucket then
            short = name:match("^capability:(.+)$")
            if short then bucket = capabilities end
        end

        if bucket then
            table.insert(bucket, {
                name = short,
                state = entry.status or "unknown",
                detail = entry.detail,
                since = entry.since,
                updatedAt = entry.updatedAt,
                data = entry.webData,
            })
        end
    end

    local function sort(list)
        table.sort(list, function(a,b) return a.name < b.name end)
    end
    sort(apps); sort(modules); sort(capabilities)
    return entries, apps, modules, capabilities
end

local function diskStats()
    local storage={mount="/"}
    local driveOk,drive=pcall(fs.getDrive,"/")
    if driveOk then storage.drive=drive end
    if type(fs.getCapacity)=="function" then
        local ok,capacity=pcall(fs.getCapacity,"/")
        if ok and type(capacity)=="number" then storage.capacity=capacity end
    end
    local freeOk,free=pcall(fs.getFreeSpace,"/")
    if freeOk and type(free)=="number" then storage.free=free end
    if storage.capacity and storage.free then
        storage.used=math.max(0,storage.capacity-storage.free)
    end
    return storage
end

local function processList()
    local out = {}
    if multishell then
        local current = multishell.getCurrent and multishell.getCurrent() or nil
        local focus = multishell.getFocus and multishell.getFocus() or nil
        for id = 1, multishell.getCount() do
            table.insert(out, {
                pid = id,
                name = multishell.getTitle(id) or ("tab-" .. tostring(id)),
                current = id == current,
                focused = id == focus,
            })
        end
    else
        table.insert(out, {
            pid = 1,
            name = shell.getRunningProgram() or "shell",
            current = true,
            focused = true,
        })
    end
    return out
end

function M.build(force)
    local now = os.epoch("utc")
    if not force and cache and (now - cacheAt) < 750 then return cache end

    local entries, apps, modules, capabilities = runtimeLists()

    cache = {
        generatedAt = now,
        uptimeMs = math.max(0, math.floor((os.clock() or 0) * 1000)),
        bootAt = now - math.max(0, math.floor((os.clock() or 0) * 1000)),
        logs = runtime.logs(80),
        schema = readJson(paths.schema),
        version = (function()
            local installed = readJson(paths.packages)
            local core = installed and installed.installed and installed.installed["core.runtime"]
            local v = type(core) == "table" and core.version or nil
            return { version = type(v) == "string" and v ~= "" and v or nil, source = "core.runtime" }
        end)(),
        apps = apps,
        modules = modules,
        capabilities = capabilities,
        runtime = entries,
        processes = processList(),
        packages = packageList(),
        tabs = processList(),
        storage = diskStats(),
        computer = {
            id=os.getComputerID and os.getComputerID() or nil,
            label=os.getComputerLabel and os.getComputerLabel() or nil
        }
    }
    cacheAt = now
    return cache
end

-- Compact, automatically collected SDK node inventory.
-- App authors do not need to declare packages, open tabs or versions.
-- Keep modem announcements small and never copy webData/whole log histories.
function M.compact(appId)
    local snapshot=M.build()
    local function slim(source,max,fields)
        local result={}
        for i,item in ipairs(type(source)=="table" and source or {}) do
            if i>max then break end
            if type(item)=="table" then
                local selected={}
                for _,key in ipairs(fields) do
                    if item[key]~=nil then selected[key]=item[key] end
                end
                result[#result+1]=selected
            end
        end
        return result
    end
    local apps=slim(snapshot.apps,20,{"name","state","detail"})
    local known=false
    for _,item in ipairs(apps) do if item.name==appId then known=true;break end end
    if type(appId)=="string" and appId~="" and not known then
        apps[#apps+1]={name=appId,state="active",detail="SDK host"}
    end
    local modules=slim(snapshot.modules,20,{"name","state","detail"})
    local tabs=slim(snapshot.tabs,16,{"pid","name","current","focused"})
    local packages=slim(snapshot.packages,48,{"name","version","kind","explicit","webConfigurable","configurable"})
    local logs={}
    for i=math.max(1,#snapshot.logs-5),#snapshot.logs do
        local entry=snapshot.logs[i]
        if type(entry)=="table" then
            logs[#logs+1]={timestamp=entry.timestamp,level=entry.level,
                component=entry.component,message=tostring(entry.message or ""):sub(1,130)}
        end
    end
    return {
        generatedAt=snapshot.generatedAt,
        uptimeMs=snapshot.uptimeMs,
        version=type(snapshot.version)=="table" and snapshot.version.version or nil,
        appCount=math.max(#apps,#snapshot.apps),
        moduleCount=#snapshot.modules,
        packageCount=#snapshot.packages,
        tabCount=#snapshot.tabs,
        storage=snapshot.storage,
        computer=snapshot.computer,
        apps=apps,modules=modules,
        processes=slim(snapshot.processes,16,{"pid","name","current","focused"}),
        tabs=tabs,packages=packages,logs=logs
    }
end

return M
