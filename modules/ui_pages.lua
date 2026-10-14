local M = {}

local function list(value)
    return type(value) == "table" and value or {}
end

function M.chunk(items, perPage)
    perPage = math.max(1, tonumber(perPage) or 1)
    local pages = {}
    items = list(items)

    if #items == 0 then return pages end

    for first = 1, #items, perPage do
        local page = {}
        local last = math.min(#items, first + perPage - 1)
        for i = first, last do table.insert(page, items[i]) end
        table.insert(pages, page)
    end
    return pages
end

function M.graphPages(data, perPage)
    local graphs = data and data.ui and data.ui.graphs
    return M.chunk(list(graphs), perPage or 4)
end

function M.metricPages(metrics, perPage)
    return M.chunk(list(metrics), perPage or 6)
end

function M.controlPages(controls, perPage)
    return M.chunk(list(controls), perPage or 6)
end

function M.groupPages(data, metricPerPage, controlPerPage)
    local out = {}
    local groups = data and data.ui and data.ui.groups

    for _, group in ipairs(list(groups)) do
        local metrics = M.metricPages(group.metrics, metricPerPage or 4)
        local controls = {}
        local allControls = data and data.ui and data.ui.controls
        for _, control in ipairs(list(allControls)) do
            if tostring(control.group or "default") == tostring(group.id or "default") then
                table.insert(controls, control)
            end
        end
        local controlChunks = M.controlPages(controls, controlPerPage or 4)

        local count = math.max(1, #metrics, #controlChunks)
        for index = 1, count do
            table.insert(out, {
                kind = "group",
                id = tostring(group.id or "group"),
                label = tostring(group.title or group.id or "GROUP"),
                part = index,
                parts = count,
                group = group,
                metrics = metrics[index] or {},
                controls = controlChunks[index] or {},
            })
        end
    end

    return out
end

function M.pocketPages(data, options)
    options = options or {}
    local pages = {}
    local homeMetrics = M.metricPages(
        data and data.ui and data.ui.metrics or {},
        options.homeMetrics or 6
    )
    if #homeMetrics == 0 then homeMetrics = { {} } end
    for index, metrics in ipairs(homeMetrics) do
        table.insert(pages, {
            kind = "home",
            id = "home",
            label = "HOME",
            part = index,
            parts = #homeMetrics,
            metrics = metrics,
        })
    end

    for _, page in ipairs(M.groupPages(
        data,
        options.groupMetrics or 4,
        options.groupControls or 4
    )) do
        table.insert(pages, page)
    end

    local graphChunks = M.graphPages(data, options.graphs or 2)
    for index, graphs in ipairs(graphChunks) do
        table.insert(pages, {
            kind = "graphs",
            id = "graphs",
            label = "GRAPHS",
            part = index,
            parts = #graphChunks,
            graphs = graphs,
        })
    end

    table.insert(pages, { kind = "machines", id = "machines", label = "MACHINES", part = 1, parts = 1 })
    table.insert(pages, { kind = "events", id = "events", label = "EVENTS", part = 1, parts = 1 })
    table.insert(pages, { kind = "system", id = "system", label = "SYSTEM", part = 1, parts = 1 })
    return pages
end

function M.pageLabel(page)
    if not page then return "?" end
    if tonumber(page.parts or 1) > 1 then
        return tostring(page.label or page.id or "?")
            .. " " .. tostring(page.part or 1)
            .. "/" .. tostring(page.parts)
    end
    return tostring(page.label or page.id or "?")
end

return M
