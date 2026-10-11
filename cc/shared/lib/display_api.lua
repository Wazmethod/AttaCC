local M = {}

local STATE_FILE = ".infra/runtime/display-publish.json"
local SELECT_FILE = ".infra/runtime/display-selection.json"

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

local function viewId(view, index)
    if type(view) ~= "table" then return tostring(index) end
    return tostring(view.id or view.key or view.name or index)
end

function M.publish(owner, descriptor)
    if type(owner) ~= "string" or owner == "" then return false, "owner required" end
    if type(descriptor) ~= "table" then return false, "descriptor table required" end

    descriptor.owner = owner
    descriptor.updatedAt = os.epoch("utc")
    return writeJson(STATE_FILE, descriptor)
end

function M.clear(owner)
    local current = readJson(STATE_FILE)
    if current and owner and current.owner and current.owner ~= owner then
        return false, "display is owned by " .. tostring(current.owner)
    end
    if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
    if fs.exists(SELECT_FILE) then fs.delete(SELECT_FILE) end
    return true
end

function M.current()
    return readJson(STATE_FILE)
end

function M.views()
    local current = M.current()
    if not current or type(current.views) ~= "table" then return {} end
    local out = {}
    for i, view in ipairs(current.views) do
        if type(view) == "table" then
            table.insert(out, {
                id = viewId(view, i),
                label = tostring(view.label or view.title or viewId(view, i)),
                index = i,
                view = view,
            })
        end
    end
    return out
end

function M.selected()
    local current = M.current()
    if not current then return nil end

    local selection = readJson(SELECT_FILE)
    local selected = selection and selection.owner == current.owner and selection.view or nil
    if selected then
        for _, item in ipairs(M.views()) do
            if item.id == selected then return selected end
        end
    end

    local configured = current.defaultView and tostring(current.defaultView) or nil
    if configured then
        for _, item in ipairs(M.views()) do
            if item.id == configured then return configured end
        end
    end

    local views = M.views()
    return views[1] and views[1].id or nil
end

function M.select(id)
    local current = M.current()
    if not current then return false, "no display descriptor published" end
    id = tostring(id or "")
    for _, item in ipairs(M.views()) do
        if item.id == id then
            return writeJson(SELECT_FILE, {
                owner = current.owner,
                view = id,
                updatedAt = os.epoch("utc"),
            })
        end
    end
    return false, "unknown display view: " .. id
end

function M.resolved()
    local current = M.current()
    if not current then return nil end

    local selected = M.selected()
    if not selected then return current end

    for _, item in ipairs(M.views()) do
        if item.id == selected then
            local out = {}
            for k, v in pairs(current) do out[k] = v end
            for k, v in pairs(item.view) do
                if k ~= "id" and k ~= "key" and k ~= "name" and k ~= "label" then
                    out[k] = v
                end
            end
            out.selectedView = selected
            out.selectedLabel = item.label
            return out
        end
    end

    return current
end

function M.status()
    local current = M.current()
    return {
        published = current ~= nil,
        owner = current and current.owner or nil,
        updatedAt = current and current.updatedAt or nil,
        selectedView = M.selected(),
        views = M.views(),
        descriptor = current,
    }
end

return M
