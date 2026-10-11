local services = require("lib.services")

local M = {}

local function titleFor(binary)
    return fs.getName(binary):gsub("%.lua$", "")
end

local function eligible(name)
    local s = services.status(name)
    if not s or not s.active or not s.binary then return nil end
    if not fs.exists(s.binary) then return nil end

    local def = services.definition(name)
    if def and def.requiresFile and not fs.exists(def.requiresFile) then return nil end
    return s
end

function M.plan()
    local planned = {}
    local seenBinary = {}

    for _, name in ipairs(services.names()) do
        local s = eligible(name)
        if s and not seenBinary[s.binary] then
            seenBinary[s.binary] = true
            table.insert(planned, {
                service = name,
                binary = s.binary,
                title = titleFor(s.binary),
            })
        end
    end

    table.sort(planned, function(a, b)
        return tostring(a.title) < tostring(b.title)
    end)
    return planned
end

function M.launchTabs()
    if not multishell then return false, "multishell unavailable" end

    local launched = {}
    for _, item in ipairs(M.plan()) do
        local id
        if shell.openTab then
            id = shell.openTab(item.binary)
        else
            local env = setmetatable({}, { __index = _ENV })
            id = multishell.launch(env, item.binary)
        end
        if id and multishell.setTitle then
            pcall(multishell.setTitle, id, item.title)
        end
        table.insert(launched, {
            id = id,
            service = item.service,
            binary = item.binary,
            title = item.title,
        })
    end
    return true, launched
end

function M.runParallel()
    local runners = {}
    for _, item in ipairs(M.plan()) do
        table.insert(runners, function() shell.run(item.binary) end)
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
