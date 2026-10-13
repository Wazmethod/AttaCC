local config = require("lib.config")
local display = require("lib.display")

local renderer = display.renderer({
    target = term,
    passTarget = false,
    config = function() return config.display or {} end,
    textModule = "lib.ui",
    graphicsModule = "lib.ui_graphics",
})

local M = {}

function M.init() return renderer:init() end
function M.draw(...) return renderer:draw(...) end
function M.click(...) return renderer:click(...) end
function M.pageCount(data) return renderer:pageCount(data) end
function M.setMode(mode) return renderer:setBackend(mode) end
function M.toggle()
    return renderer:setBackend(renderer:status().backend == "ccgraphics" and "text" or "ccgraphics")
end
function M.getStatus() return renderer:status() end

return M
