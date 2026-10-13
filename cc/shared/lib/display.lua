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

return M
