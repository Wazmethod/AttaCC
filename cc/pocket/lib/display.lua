local config = require("lib.config")

local M = { pageCount = 5 }

local backend = nil
local backendName = "none"
local backendError = nil

local function has(name)
    return type(term[name]) == "function"
end

local function supportsGraphics()
    return has("setGraphicsMode") and has("getGraphicsMode") and has("drawPixels") and has("setPixel")
end

local function loadText()
    pcall(function()
        if has("setGraphicsMode") then term.setGraphicsMode(false) end
    end)

    backend = require("lib.ui")
    backendName = "text"
    M.pageCount = backend.pageCount or 5
    return true
end

local function loadGraphics()
    local ui = require("lib.ui_graphics")
    local ok, err = pcall(ui.init, config.display and config.display.graphicsMode or 1)
    if not ok then return false, tostring(err) end

    backend = ui
    backendName = "ccgraphics"
    M.pageCount = ui.pageCount or 5
    return true
end

function M.init()
    backend = nil
    backendName = "none"
    backendError = nil

    local preferred = (config.display and config.display.preferred) or "auto"

    if preferred ~= "text" and supportsGraphics() then
        local ok, err = loadGraphics()
        if ok then
            return { backend = backendName, graphicsAvailable = true, degraded = false }
        end
        backendError = err
    elseif preferred == "ccgraphics" then
        backendError = "CC:Graphics unavailable"
    end

    local ok, err = pcall(loadText)
    if not ok then error("No usable pocket display backend: " .. tostring(err)) end

    return {
        backend = backendName,
        graphicsAvailable = supportsGraphics(),
        degraded = backendError ~= nil,
        error = backendError,
    }
end

function M.draw(...)
    if not backend then error("Pocket display backend not initialized") end

    local ok, err = pcall(backend.draw, ...)
    if ok then return true end

    if backendName ~= "text" then
        backendError = tostring(err)
        loadText()
        pcall(backend.draw, ...)
        return false, backendError
    end

    return false, tostring(err)
end

function M.click(...)
    if not backend then return nil end
    if backend.click then return backend.click(...) end
    if backend.actionAt then return backend.actionAt(...) end
    return nil
end

function M.getStatus()
    return { backend = backendName, error = backendError }
end

return M
