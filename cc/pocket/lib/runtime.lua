local M = {}

local STATE_FILE = ".infra/runtime/services.json"
local LOG_FILE = ".infra/runtime/runtime.log"

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
    local ok, data = pcall(textutils.unserializeJSON, raw)
    if ok and type(data) == "table" then return data end
    return fallback
end

local function writeJson(path, value)
    ensureParent(path)
    local ok, raw = pcall(textutils.serializeJSON, value)
    if not ok or not raw then return false end
    local tmp = path .. ".new"
    local h = fs.open(tmp, "w")
    if not h then return false end
    h.write(raw)
    h.close()
    if fs.exists(path) then fs.delete(path) end
    fs.move(tmp, path)
    return true
end

local function state()
    local data = readJson(STATE_FILE, { services = {}, updatedAt = 0 })
    data.services = type(data.services) == "table" and data.services or {}
    return data
end

function M.set(name, status, details)
    if type(name) ~= "string" or name == "" then return false end
    local data = state()
    local now = os.epoch("utc")
    local service = data.services[name] or { name = name, since = now }

    if service.status ~= status then service.since = now end
    service.status = status or service.status or "unknown"
    service.updatedAt = now

    if type(details) == "table" then
        for k, v in pairs(details) do service[k] = v end
    end

    data.services[name] = service
    data.updatedAt = now
    return writeJson(STATE_FILE, data)
end

function M.remove(name)
    local data = state()
    data.services[name] = nil
    data.updatedAt = os.epoch("utc")
    return writeJson(STATE_FILE, data)
end

function M.snapshot()
    return state()
end

function M.log(service, level, message)
    ensureParent(LOG_FILE)
    local now = os.epoch("utc")
    local line = table.concat({
        tostring(now),
        tostring(level or "info"),
        tostring(service or "runtime"),
        tostring(message or ""):gsub("[\r\n]+", " "),
    }, "\t") .. "\n"

    local h = fs.open(LOG_FILE, fs.exists(LOG_FILE) and "a" or "w")
    if h then
        h.write(line)
        h.close()
    end
end

function M.logs(limit, service)
    limit = tonumber(limit) or 50
    local out = {}
    if not fs.exists(LOG_FILE) then return out end

    local h = fs.open(LOG_FILE, "r")
    if not h then return out end
    while true do
        local line = h.readLine()
        if not line then break end
        local ts, level, svc, message = line:match("^(.-)\t(.-)\t(.-)\t(.*)$")
        if ts and (not service or svc == service) then
            table.insert(out, {
                timestamp = tonumber(ts),
                level = level,
                service = svc,
                message = message,
            })
            if #out > limit then table.remove(out, 1) end
        end
    end
    h.close()
    return out
end

return M
