local services = require("lib.services")

local M = {}

local function titleFor(binary)
    return fs.getName(binary):gsub("%.lua$", "")
end

local function eligible(name)
    local s = services.status(name)
    if not s or not s.active or not s.binary then return nil end
    if not fs.exists(s.binary) then return nil end
    return s
end

function M.isRunning(binary)
    if not multishell or not binary then return false end
    local wanted = titleFor(binary)
    for id = 1, multishell.getCount() do
        if multishell.getTitle(id) == wanted then return true, id end
    end
    return false
end

local function dependencyRank(name, stack, memo)
    memo = memo or {}
    if memo[name] then return memo[name] end
    stack = stack or {}
    if stack[name] then return 0 end
    stack[name] = true

    local s = services.status(name)
    local rank = 0
    if s then
        for _, dep in ipairs(s.depends or {}) do
            rank = math.max(rank, dependencyRank(dep, stack, memo) + 1)
        end
    end

    stack[name] = nil
    memo[name] = rank
    return rank
end

function M.plan()
    local planned = {}
    local byBinary = {}
    local memo = {}

    for _, name in ipairs(services.names()) do
        local s = eligible(name)
        if s then
            local item = byBinary[s.binary]
            if not item then
                item = {
                    service = name,
                    services = {},
                    binary = s.binary,
                    title = titleFor(s.binary),
                    rank = 0,
                }
                byBinary[s.binary] = item
                table.insert(planned, item)
            end
            table.insert(item.services, name)
            item.rank = math.max(item.rank, dependencyRank(name, {}, memo))
        end
    end

    for _, item in ipairs(planned) do
        table.sort(item.services)
        item.service = item.services[1] or item.service
    end

    table.sort(planned, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return tostring(a.title) < tostring(b.title)
    end)
    return planned
end

local function serviceArg(item)
    return table.concat(item.services or { item.service }, ",")
end

function M.launchTabs()
    if not multishell then return false, "multishell unavailable" end

    local launched = {}
    for _, item in ipairs(M.plan()) do
        local running = M.isRunning(item.binary)
        if not running then
            local id
            if shell.openTab then
                id = shell.openTab("servicerun.lua", item.binary, serviceArg(item))
            else
                local env = setmetatable({}, { __index = _ENV })
                id = multishell.launch(env, "servicerun.lua", item.binary, serviceArg(item))
            end
            if id and multishell.setTitle then
                pcall(multishell.setTitle, id, item.title)
            end
            table.insert(launched, {
                id = id,
                service = item.service,
                services = item.services,
                binary = item.binary,
                title = item.title,
            })
        end
    end
    return true, launched
end

function M.runParallel()
    local runners = {}
    for _, item in ipairs(M.plan()) do
        local binary = item.binary
        local names = serviceArg(item)
        table.insert(runners, function()
            shell.run("servicerun.lua", binary, names)
        end)
    end

    if #runners == 0 then return true end
    if #runners == 1 then
        runners[1]()
        return true
    end
    parallel.waitForAny(table.unpack(runners))
    return true
end

return M
