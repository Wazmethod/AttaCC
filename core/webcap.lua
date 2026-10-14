local runtime = require("lib.runtime")

local M = {}

function M.publish(name, data)
    name = tostring(name or "")
    if name == "" then return false, "capability name required" end
    if type(data) ~= "table" then return false, "data table required" end

    local key = "capability:" .. name
    local snap = runtime.snapshot()
    local current = snap.entries and snap.entries[key] or nil
    local state = current and current.status or "active"

    return runtime.set(key, state, {
        webData = data,
        webUpdatedAt = os.epoch("utc"),
    })
end

function M.clear(name)
    name = tostring(name or "")
    local key = "capability:" .. name
    local snap = runtime.snapshot()
    local current = snap.entries and snap.entries[key] or nil
    if not current then return true end
    return runtime.set(key, current.status or "active", {
        webData = {},
        webUpdatedAt = os.epoch("utc"),
    })
end

return M
