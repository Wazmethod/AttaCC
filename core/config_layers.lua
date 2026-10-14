-- Layered AttaCC configuration. Legacy profile overrides remain supported.
-- Ownership: apps.lua = application configuration, io.lua = physical IO,
-- machine.lua = stable logical identity, storage.lua = sync destination.
local M = {}

local function merge(base, override)
    if type(override) ~= "table" then return base end
    for k,v in pairs(override) do
        if type(v) == "table" and type(base[k]) == "table" then
            merge(base[k], v)
        else
            base[k] = v
        end
    end
    return base
end

local function read(path)
    if not fs.exists(path) then return nil end
    local ok, data = pcall(dofile, path)
    if not ok or type(data) ~= "table" then
        error("Invalid AttaCC config: " .. path .. ": " .. tostring(data))
    end
    return data
end

function M.load(config)
    -- Last-write precedence is explicit: built-ins < legacy < apps/io.
    merge(config, read("/etc/profile.lua"))
    merge(config, read("/etc/apps.lua"))
    local io = read("/etc/io.lua")
    if io then
        config.io = config.io or {}
        merge(config.io, io.io or io)
    end
    return config
end

function M.read(path)
    return read(path) or {}
end

return M
