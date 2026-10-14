local config = require("lib.config")
local display = require("lib.display")

local renderer = display.renderer({
    config = function() return config.display or {} end,
    textModule = "lib.dashboard_view_text",
    graphicsModule = "lib.dashboard_view_graphics",
})

local M = {}
function M.init(mon) return renderer:init(mon) end
function M.draw(mon,...) return renderer:draw(...) end
function M.actionAt(x,y) return renderer:actionAt(x,y) end
function M.getStatus() return renderer:status() end
function M.shutdown(mon) return renderer:shutdown() end
return M
