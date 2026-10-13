local runtime = require("lib.runtime")

local M = {}

function M.publish(serviceName, data)
    serviceName = tostring(serviceName or ""):gsub("%.service$", "")
    if serviceName == "" then return false, "service name required" end
    if type(data) ~= "table" then return false, "data table required" end

    local snap = runtime.snapshot()
    local current = snap.services and snap.services["service:" .. serviceName] or nil
    local state = current and current.status or "active"

    return runtime.set("service:" .. serviceName, state, {
        webData = data,
        webUpdatedAt = os.epoch("utc"),
    })
end

function M.clear(serviceName)
    serviceName = tostring(serviceName or ""):gsub("%.service$", "")
    local snap = runtime.snapshot()
    local current = snap.services and snap.services["service:" .. serviceName] or nil
    if not current then return true end
    return runtime.set("service:" .. serviceName, current.status or "active", {
        webData = {},
        webUpdatedAt = os.epoch("utc"),
    })
end

return M
