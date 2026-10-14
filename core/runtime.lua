local paths = require("lib.paths")

paths.ensure()

local M = {}
local STATE_FILE = paths.runtimeState
local LOG_FILE = paths.journal

local function humanTime(epochMs)
    local seconds = math.floor((tonumber(epochMs) or 0) / 1000)
    local ok, value = pcall(os.date, "!%Y-%m-%d %H:%M:%S", seconds)
    return ok and value or tostring(epochMs)
end

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
    local data = readJson(STATE_FILE, { entries = {}, updatedAt = 0 })
    data.entries = type(data.entries) == "table" and data.entries or {}
    return data
end

function M.set(name, status, details)
    if type(name) ~= "string" or name == "" then return false end
    local data = state()
    local now = os.epoch("utc")
    local entry = data.entries[name] or { name = name, since = now }

    if entry.status ~= status then entry.since = now end
    entry.status = status or entry.status or "unknown"
    entry.updatedAt = now

    if type(details) == "table" then
        for k, v in pairs(details) do entry[k] = v end
    end

    data.entries[name] = entry
    data.updatedAt = now
    return writeJson(STATE_FILE, data)
end

function M.remove(name)
    local data = state()
    data.entries[name] = nil
    data.updatedAt = os.epoch("utc")
    return writeJson(STATE_FILE, data)
end

function M.snapshot()
    return state()
end

function M.log(component, level, message)
    local now = os.epoch("utc")
    local line = table.concat({
        humanTime(now),
        tostring(level or "info"),
        tostring(component or "runtime"),
        tostring(message or ""):gsub("[\r\n]+", " "),
    }, "\t") .. "\n"

    paths.ensureComponentLog(component)
    for _, file in ipairs({ LOG_FILE, paths.componentLog(component) }) do
        ensureParent(file)
        local h = fs.open(file, fs.exists(file) and "a" or "w")
        if h then h.write(line) h.close() end
    end
end

function M.logs(limit, component)
    limit = tonumber(limit) or 50
    local out = {}
    local file = component and paths.componentLog(component) or LOG_FILE
    if not fs.exists(file) then return out end

    local h = fs.open(file, "r")
    if not h then return out end
    while true do
        local line = h.readLine()
        if not line then break end
        local ts, level, name, message = line:match("^(.-)\t(.-)\t(.-)\t(.*)$")
        if ts and (not component or name == component) then
            table.insert(out, {
                timestamp = tonumber(ts),
                date = tonumber(ts) and humanTime(tonumber(ts)) or ts,
                level = level,
                component = name,
                message = message,
            })
            if #out > limit then table.remove(out, 1) end
        end
    end
    h.close()
    return out
end

function M.logPath(component)
    return component and paths.componentLog(component) or LOG_FILE
end

return M
