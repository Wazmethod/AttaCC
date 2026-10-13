local config = require("lib.config")

local M = {}
local backend = nil
local backendName = "none"
local backendError = nil

local function hasMethod(object, name)
    return object and type(object[name]) == "function"
end

local function supportsCCGraphics(mon)
    return hasMethod(mon, "setGraphicsMode")
        and hasMethod(mon, "getGraphicsMode")
        and hasMethod(mon, "drawPixels")
        and hasMethod(mon, "setPixel")
end

local function loadText(mon)
    pcall(function()
        if hasMethod(mon, "setGraphicsMode") then mon.setGraphicsMode(false) end
    end)
    if hasMethod(mon, "setTextScale") then
        pcall(mon.setTextScale, config.display.textScale or 0.5)
    end
    backend = require("lib.ui")
    backendName = "text"
    return true
end

local function loadGraphics(mon)
    local ui = require("lib.ui_graphics")
    local ok, err = pcall(ui.init, mon, config.display.graphicsMode or 1)
    if not ok then return false, tostring(err) end
    backend = ui
    backendName = "ccgraphics"
    return true
end

function M.init(mon)
    backend = nil
    backendName = "none"
    backendError = nil

    -- Force a known monitor text geometry before CC:Graphics inspects the
    -- framebuffer. Joined monitors may otherwise retain an old/default scale
    -- and produce incorrect pixel dimensions for the dashboard layout.
    if hasMethod(mon, "setTextScale") then
        pcall(mon.setTextScale, (config.display and config.display.textScale) or 0.5)
    end

    local preferred = (config.display and config.display.preferred) or "auto"

    if preferred ~= "text" and supportsCCGraphics(mon) then
        local ok, err = loadGraphics(mon)
        if ok then
            return { backend = backendName, graphicsAvailable = true, degraded = false }
        end
        backendError = err
    elseif preferred == "ccgraphics" then
        backendError = "CC:Graphics API unavailable on monitor"
    end

    local ok, err = pcall(loadText, mon)
    if not ok then error("No usable display backend: " .. tostring(err)) end

    return {
        backend = backendName,
        graphicsAvailable = supportsCCGraphics(mon),
        degraded = backendError ~= nil,
        error = backendError,
    }
end

function M.draw(mon, ...)
    if not backend then error("Display backend not initialized") end

    local ok, err = pcall(backend.draw, mon, ...)
    if ok then return true end

    if backendName ~= "text" then
        backendError = tostring(err)
        loadText(mon)
        pcall(backend.draw, mon, ...)
        return false, backendError
    end

    return false, tostring(err)
end

function M.actionAt(x, y)
    if backend and backend.actionAt then return backend.actionAt(x, y) end
    return nil
end

function M.getStatus()
    return { backend = backendName, error = backendError }
end

function M.shutdown(mon)
    if backend and backend.shutdown then
        pcall(backend.shutdown, mon)
    elseif hasMethod(mon, "setGraphicsMode") then
        pcall(mon.setGraphicsMode, false)
    end
end

return M
