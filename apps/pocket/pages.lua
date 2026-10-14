local dashboard = require("lib.dashboard")
local M = {}
local offsets = { data = 1, graphs = 1, controls = 1 }
local order = { "data", "graphs", "controls" }

local function configPages(data)
    return dashboard.machinePages(data, {
        dataPerPage = 6,
        graphsPerPage = 2,
        controlsPerPage = 6,
    })
end

function M.build(data)
    local pages = {
        {kind="home",label="HOME",part=1,parts=1},
        {kind="machines",label="MACHINE",part=1,parts=1},
    }
    local all = configPages(data)
    for _, kind in ipairs(order) do
        local group = {}
        for _, def in ipairs(all) do
            if def.kind == kind then group[#group+1] = def end
        end
        if #group > 0 then
            local index = math.min(math.max(offsets[kind] or 1, 1), #group)
            offsets[kind] = index
            local selected = group[index]
            local entry = {}
            for k,v in pairs(selected) do entry[k] = v end
            entry.subIndex = index
            entry.subTotal = #group
            pages[#pages+1] = entry
        end
    end
    pages[#pages+1] = {kind="events",label="EVENTS",part=1,parts=1}
    pages[#pages+1] = {kind="system",label="SYSTEM",part=1,parts=1}
    return pages
end

function M.shift(kind, delta, data)
    if not offsets[kind] then return false end
    local total = 0
    for _, def in ipairs(configPages(data)) do
        if def.kind == kind then total = total + 1 end
    end
    if total == 0 then return false end
    offsets[kind] = ((offsets[kind] + delta - 1) % total) + 1
    return true
end

return M
