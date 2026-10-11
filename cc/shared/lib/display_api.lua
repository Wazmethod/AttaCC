local M = {}

local STATE_FILE = ".infra/runtime/display-publish.json"

local function ensureParent(path)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
end

local function writeJson(path, value)
    ensureParent(path)
    local raw = textutils.serializeJSON(value)
    local tmp = path .. ".new"
    local h = fs.open(tmp, "w")
    if not h then return false, "cannot open " .. tmp end
    h.write(raw)
    h.close()
    if fs.exists(path) then fs.delete(path) end
    fs.move(tmp, path)
    return true
end

local function readJson()
    if not fs.exists(STATE_FILE) then return nil end
    local h = fs.open(STATE_FILE, "r")
    if not h then return nil end
    local raw = h.readAll()
    h.close()
    local ok, value = pcall(textutils.unserializeJSON, raw)
    if ok and type(value) == "table" then return value end
    return nil
end

function M.publish(owner, descriptor)
    if type(owner) ~= "string" or owner == "" then return false, "owner required" end
    if type(descriptor) ~= "table" then return false, "descriptor table required" end

    descriptor.owner = owner
    descriptor.updatedAt = os.epoch("utc")
    return writeJson(STATE_FILE, descriptor)
end

function M.clear(owner)
    local current = readJson()
    if current and owner and current.owner and current.owner ~= owner then
        return false, "display is owned by " .. tostring(current.owner)
    end
    if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
    return true
end

function M.current()
    return readJson()
end

function M.status()
    local current = readJson()
    return {
        published = current ~= nil,
        owner = current and current.owner or nil,
        updatedAt = current and current.updatedAt or nil,
        descriptor = current,
    }
end

return M
