local uiPages = require("lib.ui_pages")

local M = {}

local function list(value)
    return type(value) == "table" and value or {}
end

local function categoryMap(ui, kind)
    local out = {}
    local categories = ui and ui.categories and ui.categories[kind]
    for _, item in ipairs(list(categories)) do
        local id = tostring(item.id or item.key or item.title or "default")
        out[id] = {
            id = id,
            title = tostring(item.title or item.label or id):upper(),
            order = tonumber(item.order) or 999,
        }
    end
    return out
end

local function orderedCategories(ui, kind, items, groupField)
    local definitions = categoryMap(ui, kind)
    local seen = {}

    for _, item in ipairs(list(items)) do
        local id = tostring(item[groupField or "group"] or "default")
        if not definitions[id] then
            definitions[id] = { id = id, title = string.upper(id), order = 999 }
        end
        seen[id] = true
    end

    local out = {}
    for id, meta in pairs(definitions) do
        if seen[id] or #list(ui and ui.categories and ui.categories[kind]) > 0 then
            table.insert(out, meta)
        end
    end
    table.sort(out, function(a,b)
        if a.order ~= b.order then return a.order < b.order end
        return a.title < b.title
    end)
    return out
end

local function grouped(items, field)
    local out = {}
    for _, item in ipairs(list(items)) do
        local id = tostring(item[field or "group"] or "default")
        out[id] = out[id] or {}
        table.insert(out[id], item)
    end
    return out
end

local function appendChunkedPages(out, kind, categories, buckets, perPage)
    for _, category in ipairs(categories) do
        local chunks = uiPages.chunk(buckets[category.id] or {}, perPage)
        if #chunks == 0 then chunks = { {} } end
        for index, chunk in ipairs(chunks) do
            table.insert(out, {
                kind = kind,
                category = category.id,
                categoryTitle = category.title,
                label = category.title,
                part = index,
                parts = #chunks,
                items = chunk,
            })
        end
    end
end

function M.machinePages(data, options)
    options = options or {}
    local ui = data and data.ui or {}
    local pages = {}

    local dataItems = {}
    for _, group in ipairs(list(ui.groups)) do
        local id = tostring(group.id or "default")
        for _, metric in ipairs(list(group.metrics)) do
            local item = {}
            for k,v in pairs(metric) do item[k] = v end
            item.group = id
            item.groupTitle = group.title or id
            table.insert(dataItems, item)
        end
    end

    local dataCats = orderedCategories(ui, "data", dataItems, "group")
    local graphCats = orderedCategories(ui, "graphs", ui.graphs, "group")
    local controlCats = orderedCategories(ui, "controls", ui.controls, "group")

    appendChunkedPages(
        pages, "data", dataCats, grouped(dataItems, "group"),
        options.dataPerPage or 8
    )
    appendChunkedPages(
        pages, "graphs", graphCats, grouped(ui.graphs, "group"),
        options.graphsPerPage or 4
    )
    appendChunkedPages(
        pages, "controls", controlCats, grouped(ui.controls, "group"),
        options.controlsPerPage or 8
    )

    return pages
end

function M.pagesForKind(data, kind, options)
    local out = {}
    for _, page in ipairs(M.machinePages(data, options)) do
        if page.kind == kind then table.insert(out, page) end
    end
    return out
end

function M.pageLabel(page)
    if not page then return "?" end
    local label = tostring(page.categoryTitle or page.label or page.kind or "?")
    if tonumber(page.parts or 1) > 1 then
        label = label .. " " .. tostring(page.part or 1) .. "/" .. tostring(page.parts)
    end
    return label
end

function M.findPage(pages, kind, index)
    local subset = {}
    for _, page in ipairs(list(pages)) do
        if page.kind == kind then table.insert(subset, page) end
    end
    if #subset == 0 then return nil, 0 end
    index = math.max(1, math.min(#subset, tonumber(index) or 1))
    return subset[index], #subset
end

return M
