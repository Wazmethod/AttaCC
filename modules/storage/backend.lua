local paths = require("lib.paths")

local M = {}

local function ensureParent(path)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
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
    ensureParent(path)
    local ok, raw = pcall(textutils.serializeJSON, value)
    if not ok or not raw then return false, "serialization failed" end
    local tmp = path .. ".new"
    local h = fs.open(tmp, "w")
    if not h then return false, "cannot open store" end
    h.write(raw)
    h.close()
    if fs.exists(path) then fs.delete(path) end
    fs.move(tmp, path)
    return true
end

local function validName(value, maxLength)
    return type(value) == "string"
        and value ~= ""
        and #value <= maxLength
        and not value:find("[^%w%._:%-]")
end

function M.new(config)
    local settings = config.storage or {}
    local file = settings.file or fs.combine(paths.storage, "store.json")
    local maxValueBytes = tonumber(settings.maxValueBytes) or 4096
    local maxKeys = tonumber(settings.maxKeys) or 512

    local self = { file = file }

    local function loadStore()
        local data = readJson(file, { format = 1, namespaces = {}, updatedAt = 0 })
        data.namespaces = type(data.namespaces) == "table" and data.namespaces or {}
        return data
    end

    local function countKeys(data)
        local count = 0
        for _, bucket in pairs(data.namespaces or {}) do
            if type(bucket) == "table" then
                for _ in pairs(bucket) do count = count + 1 end
            end
        end
        return count
    end

    function self:ping()
        return {
            module = settings.module or "network.storage",
            localBackend = true,
            version = 1,
        }
    end

    function self:namespaces()
        local data = loadStore()
        local out = {}
        for name in pairs(data.namespaces) do table.insert(out, name) end
        table.sort(out)
        return out
    end

    function self:list(namespace)
        if not validName(namespace, 64) then return nil, "invalid namespace" end
        local data = loadStore()
        local bucket = data.namespaces[namespace]
        if type(bucket) ~= "table" then return {} end
        local out = {}
        for key in pairs(bucket) do table.insert(out, key) end
        table.sort(out)
        return out
    end

    function self:get(namespace, key)
        if not validName(namespace, 64) then return nil, "invalid namespace" end
        if not validName(key, 128) then return nil, "invalid key" end
        local data = loadStore()
        local bucket = data.namespaces[namespace]
        if type(bucket) ~= "table" then return nil end
        local entry = bucket[key]
        return entry and entry.value or nil
    end

    function self:set(namespace, key, value, origin)
        if not validName(namespace, 64) then return nil, "invalid namespace" end
        if not validName(key, 128) then return nil, "invalid key" end

        local okSerialized, serialized = pcall(textutils.serializeJSON, value)
        if not okSerialized or not serialized then return nil, "value is not serializable" end
        if #serialized > maxValueBytes then return nil, "value exceeds maxValueBytes" end

        local data = loadStore()
        local bucket = data.namespaces[namespace]
        if type(bucket) ~= "table" then
            bucket = {}
            data.namespaces[namespace] = bucket
        end

        if not bucket[key] and countKeys(data) >= maxKeys then
            return nil, "store key limit reached"
        end

        bucket[key] = {
            value = value,
            updatedAt = os.epoch("utc"),
            updatedBy = origin,
        }
        data.updatedAt = os.epoch("utc")
        local ok, err = writeJson(file, data)
        if not ok then return nil, err end
        return true
    end

    function self:delete(namespace, key)
        if not validName(namespace, 64) then return nil, "invalid namespace" end
        if not validName(key, 128) then return nil, "invalid key" end
        local data = loadStore()
        local bucket = data.namespaces[namespace]
        if type(bucket) == "table" then bucket[key] = nil end
        data.updatedAt = os.epoch("utc")
        local ok, err = writeJson(file, data)
        if not ok then return nil, err end
        return true
    end

    function self:stats()
        local data = loadStore()
        local namespaces = 0
        local keys = 0
        for _, bucket in pairs(data.namespaces or {}) do
            namespaces = namespaces + 1
            if type(bucket) == "table" then
                for _ in pairs(bucket) do keys = keys + 1 end
            end
        end
        return {
            namespaces = namespaces,
            keys = keys,
            maxKeys = maxKeys,
            maxValueBytes = maxValueBytes,
            updatedAt = data.updatedAt or 0,
        }
    end

    return self
end

return M
