local config = require("lib.config")
local display = require("lib.display")

local function transformTouch(x, y, backendName, backend, target, displayConfig)
    local profile = displayConfig.touchProfile or "normal"

    if backendName ~= "ccgraphics" or not backend or not backend.getDebugGeometry then
        return x, y
    end

    local g = backend.getDebugGeometry()
    local w = g and g.pixelWidth or 0
    if not w or w <= 0 then return x, y end

    if profile == "angled3" then
        local third = w / 3
        if x < third then
            x = (third - 1) - x
        elseif x >= third * 2 then
            local localX = x - third * 2
            local wingW = w - third * 2
            x = third * 2 + (wingW - 1 - localX)
        end
    elseif profile == "mirror_x" then
        x = w - 1 - x
    end

    return math.floor(x + 0.5), math.floor(y + 0.5)
end

local renderer = display.renderer({
    config = function() return config.display or {} end,
    textModule = "lib.ui",
    graphicsModule = "lib.ui_graphics",
    transformTouch = transformTouch,
})

local M = {}

function M.init(mon) return renderer:init(mon) end
function M.draw(mon, ...) return renderer:draw(...) end
function M.actionAt(x, y) return renderer:actionAt(x, y) end
function M.setBackend(mon, requested)
    if mon then renderer.target = mon end
    return renderer:setBackend(requested)
end
function M.toggleBackend() return renderer:toggleBackend() end
function M.availableBackends() return renderer:availableBackends() end
function M.getStatus() return renderer:status() end
function M.getBackend() return renderer:status().backend end
function M.shutdown(mon) return renderer:shutdown() end

return M
