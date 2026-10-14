local M = {}

M.EVENT = "attacc_bus"

local handlers = {}

local function matches(pattern, topic)
    if pattern == "*" then return true end
    if pattern == topic then return true end
    if pattern:sub(-2) == ".*" then
        local prefix = pattern:sub(1, -2)
        return topic:sub(1, #prefix) == prefix
    end
    return false
end

function M.on(topic, handler)
    if type(topic) ~= "string" or topic == "" then return nil, "topic required" end
    if type(handler) ~= "function" then return nil, "handler required" end

    local entry = { topic = topic, handler = handler }
    table.insert(handlers, entry)
    return entry
end

function M.off(token)
    for i, entry in ipairs(handlers) do
        if entry == token then
            table.remove(handlers, i)
            return true
        end
    end
    return false
end

function M.emit(topic, payload, meta)
    if type(topic) ~= "string" or topic == "" then return false, "topic required" end
    os.queueEvent(M.EVENT, topic, payload, meta or {})
    return true
end

function M.handle(event, topic, payload, meta)
    if event ~= M.EVENT then return false end

    local handled = false
    for _, entry in ipairs(handlers) do
        if matches(entry.topic, topic) then
            handled = true
            local ok, err = pcall(entry.handler, payload, meta or {}, topic)
            if not ok then
                os.queueEvent("attacc_bus_error", topic, tostring(err))
            end
        end
    end
    return handled
end

function M.dispatch(...)
    local event, p1, p2, p3 = ...
    return M.handle(event, p1, p2, p3)
end

return M
