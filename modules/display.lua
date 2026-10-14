local M = {}

local function measureDefault()
    return 1
end

function M.find(name)
    if name and name ~= "" and name ~= "auto" then
        if not peripheral.isPresent(name) then return nil, "display peripheral missing: " .. tostring(name) end
        local wrapped = peripheral.wrap(name)
        if not wrapped or peripheral.getType(name) ~= "monitor" then
            return nil, "peripheral is not a monitor: " .. tostring(name)
        end
        return wrapped, name
    end

    local monitor = peripheral.find("monitor")
    if not monitor then return nil, "no monitor detected" end
    return monitor, peripheral.getName(monitor)
end

function M.geometry(target)
    if not target or type(target.getSize) ~= "function" then
        return nil, nil, "display unavailable"
    end
    local ok, w, h = pcall(target.getSize)
    if not ok then return nil, nil, tostring(w) end
    return w, h
end

function M.paginate(items, width, height, options)
    options = options or {}
    local headerRows = tonumber(options.headerRows) or 0
    local footerRows = tonumber(options.footerRows) or 0
    local gapRows = tonumber(options.gapRows) or 0
    local measure = options.measure or measureDefault
    local available = math.max(1, (tonumber(height) or 1) - headerRows - footerRows)

    local pages = {}
    local page = {}
    local used = 0

    for index, item in ipairs(items or {}) do
        local rows = tonumber(measure(item, width, index)) or 1
        rows = math.max(1, rows)
        local required = rows + (#page > 0 and gapRows or 0)

        if #page > 0 and used + required > available then
            table.insert(pages, page)
            page = {}
            used = 0
            required = rows
        end

        table.insert(page, item)
        used = used + required
    end

    if #page > 0 or #pages == 0 then table.insert(pages, page) end
    return pages
end

function M.new(target, options)
    local self = {
        target = target,
        options = options or {},
        items = {},
        pages = { {} },
        page = 1,
        width = nil,
        height = nil,
    }

    function self:refresh(items)
        if items ~= nil then self.items = items end
        local w, h, err = M.geometry(self.target)
        if not w then return false, err end

        local changed = w ~= self.width or h ~= self.height
        self.width, self.height = w, h
        self.pages = M.paginate(self.items, w, h, self.options)
        if self.page > #self.pages then self.page = #self.pages end
        if self.page < 1 then self.page = 1 end
        return true, changed
    end

    function self:current()
        return self.pages[self.page] or {}, self.page, #self.pages
    end

    function self:next()
        if self.page < #self.pages then self.page = self.page + 1 end
        return self:current()
    end

    function self:previous()
        if self.page > 1 then self.page = self.page - 1 end
        return self:current()
    end

    function self:select(index)
        index = tonumber(index)
        if not index or index < 1 or index > #self.pages then return false end
        self.page = index
        return true
    end

    return self
end

local function hasMethod(object, name)
    return object and type(object[name]) == "function"
end

function M.supportsGraphics(target)
    return hasMethod(target, "setGraphicsMode")
        and hasMethod(target, "getGraphicsMode")
        and hasMethod(target, "drawPixels")
        and hasMethod(target, "setPixel")
end

function M.renderer(options)
    options = options or {}

    local self = {
        target = options.target,
        backend = nil,
        backendName = "none",
        backendError = nil,
    }

    local function displayConfig()
        if type(options.config) == "function" then return options.config() or {} end
        return options.config or {}
    end

    local function target()
        return self.target or term
    end

    local function callInit(module, tgt, cfg)
        if not module.init then return true end
        if options.passTarget == false then
            return pcall(module.init, cfg.graphicsMode or 1)
        end
        return pcall(module.init, tgt, cfg.graphicsMode or 1)
    end

    local function loadText()
        local tgt = target()
        local cfg = displayConfig()

        pcall(function()
            if hasMethod(tgt, "setGraphicsMode") then tgt.setGraphicsMode(false) end
        end)

        if hasMethod(tgt, "setTextScale") and cfg.forceTextScale ~= false then
            pcall(tgt.setTextScale, cfg.textScale or 0.5)
        end

        self.backend = require(options.textModule or "lib.ui")
        self.backendName = "text"
        return true
    end

    local function loadGraphics()
        local tgt = target()
        if not M.supportsGraphics(tgt) then
            return false, "CC:Graphics API unavailable"
        end

        local ui = require(options.graphicsModule or "lib.ui_graphics")
        local ok, err = callInit(ui, tgt, displayConfig())
        if not ok then return false, tostring(err) end

        self.backend = ui
        self.backendName = "ccgraphics"
        return true
    end

    function self:init(targetOverride)
        if targetOverride then self.target = targetOverride end

        self.backend = nil
        self.backendName = "none"
        self.backendError = nil

        local cfg = displayConfig()
        local tgt = target()

        if hasMethod(tgt, "setTextScale") and cfg.forceTextScale ~= false then
            pcall(tgt.setTextScale, cfg.textScale or 0.5)
        end

        local preferred = cfg.preferred or "auto"
        if preferred ~= "text" and M.supportsGraphics(tgt) then
            local ok, err = loadGraphics()
            if ok then
                return {
                    backend = self.backendName,
                    graphicsAvailable = true,
                    degraded = false,
                }
            end
            self.backendError = err
        elseif preferred == "ccgraphics" then
            self.backendError = "CC:Graphics API unavailable"
        end

        local ok, err = pcall(loadText)
        if not ok then error("No usable display backend: " .. tostring(err)) end

        return {
            backend = self.backendName,
            graphicsAvailable = M.supportsGraphics(tgt),
            degraded = self.backendError ~= nil,
            error = self.backendError,
        }
    end

    function self:setBackend(requested)
        requested = tostring(requested or "auto")
        self.backendError = nil

        if requested == "text" then
            local ok, err = pcall(loadText)
            if not ok then return false, tostring(err) end
            return true, self:status()
        end

        if requested == "ccgraphics" or requested == "graphics" then
            local ok, err = loadGraphics()
            if not ok then
                self.backendError = tostring(err)
                return false, self.backendError
            end
            return true, self:status()
        end

        return false, "unsupported display backend: " .. requested
    end

    function self:draw(...)
        if not self.backend then error("Display backend not initialized") end

        local tgt = target()
        local ok, err
        if options.passTarget == false then
            ok, err = pcall(self.backend.draw, ...)
        else
            ok, err = pcall(self.backend.draw, tgt, ...)
        end

        if ok then return true end

        if self.backendName ~= "text" then
            self.backendError = tostring(err)
            loadText()
            if options.passTarget == false then
                pcall(self.backend.draw, ...)
            else
                pcall(self.backend.draw, tgt, ...)
            end
            return false, self.backendError
        end

        return false, tostring(err)
    end

    local function transform(x, y)
        if type(options.transformTouch) == "function" then
            return options.transformTouch(
                x, y, self.backendName, self.backend, target(), displayConfig()
            )
        end
        return x, y
    end

    function self:actionAt(x, y)
        x, y = transform(x, y)
        if self.backend and self.backend.actionAt then
            return self.backend.actionAt(x, y)
        end
        return nil
    end

    function self:click(...)
        if not self.backend then return nil end
        if self.backend.click then return self.backend.click(...) end
        if self.backend.actionAt then return self.backend.actionAt(...) end
        return nil
    end

    function self:pageCount(data)
        if self.backend and type(self.backend.pageCount) == "function" then
            return self.backend.pageCount(data)
        end
        return 1
    end

    function self:status()
        return {
            backend = self.backendName,
            error = self.backendError,
            graphicsAvailable = M.supportsGraphics(target()),
        }
    end

    function self:shutdown()
        local tgt = target()
        if self.backend and self.backend.shutdown then
            pcall(self.backend.shutdown, tgt)
        elseif hasMethod(tgt, "setGraphicsMode") then
            pcall(tgt.setGraphicsMode, false)
        end
    end

    return self
end

return M
