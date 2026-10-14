local config = require("lib.config")
local display = require("lib.display")

local nativeTerm = term.current()
local monitor = nil
local monitorRenderer = nil

local function textConfig()
    local out = {}
    for k,v in pairs(config.display or {}) do out[k]=v end
    out.preferred = "text"
    return out
end

local textRenderer = display.renderer({
    target = nativeTerm,
    passTarget = false,
    config = textConfig,
    textModule = "lib.ui",
    graphicsModule = "lib.ui_graphics",
})

local function withTarget(target, fn)
    local previous = term.redirect(target)
    local ok, a, b, c = pcall(fn)
    term.redirect(previous)
    if not ok then error(a) end
    return a, b, c
end

local M = {}

function M.init()
    return withTarget(nativeTerm, function()
        return textRenderer:init()
    end)
end

function M.setMonitor(target)
    if monitorRenderer and monitor then
        pcall(function()
            withTarget(monitor, function() monitorRenderer:shutdown() end)
        end)
    end

    monitor = target
    monitorRenderer = nil

    if not monitor then return false, "no monitor" end

    monitorRenderer = display.renderer({
        target = monitor,
        passTarget = false,
        config = function() return config.display or {} end,
        textModule = "lib.ui",
        graphicsModule = "lib.ui_graphics",
    })

    local ok, status = pcall(function()
        return withTarget(monitor, function()
            return monitorRenderer:init()
        end)
    end)
    if not ok then
        monitorRenderer = nil
        return false, tostring(status)
    end
    return true, status
end

function M.draw(...)
    local args = { ... }

    withTarget(nativeTerm, function()
        textRenderer:draw(table.unpack(args))
    end)

    if monitorRenderer and monitor then
        pcall(function()
            withTarget(monitor, function()
                monitorRenderer:draw(table.unpack(args))
            end)
        end)
    end
end

function M.click(...)
    local args = { ... }
    return withTarget(nativeTerm, function()
        return textRenderer:click(table.unpack(args))
    end)
end

function M.monitorClick(x, y)
    if not monitorRenderer or not monitor then return nil end
    return withTarget(monitor, function()
        return monitorRenderer:actionAt(x, y)
    end)
end

function M.pageCount(data)
    return textRenderer:pageCount(data)
end

function M.setMode(mode)
    if not monitorRenderer or not monitor then return false, "no external monitor" end
    return withTarget(monitor, function()
        return monitorRenderer:setBackend(mode)
    end)
end

function M.toggle()
    if not monitorRenderer or not monitor then return false, "no external monitor" end
    return withTarget(monitor, function()
        local current = monitorRenderer:status().backend
        return monitorRenderer:setBackend(current == "ccgraphics" and "text" or "ccgraphics")
    end)
end

function M.getStatus()
    return {
        terminal = textRenderer:status(),
        monitor = monitorRenderer and monitorRenderer:status() or nil,
    }
end

return M
