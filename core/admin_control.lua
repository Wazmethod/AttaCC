local M = {}

local function launch(program, title, ...)
    if multishell and multishell.launch then
        local env = {}
        setmetatable(env, { __index = _ENV })
        local id = multishell.launch(env, program, ...)
        if id and title and multishell.setTitle then
            pcall(multishell.setTitle, id, title)
        end
        -- multishell.launch runs the program directly. The tab disappears when
        -- pkgctl exits instead of dropping into a persistent shell.
        return true, { pid = id, started = true, autoClose = true }
    end

    local ok = shell.run(program, ...)
    return ok ~= false, { started = true, synchronous = true }
end

function M.handle(request)
    if type(request) ~= "table" then return false, "invalid request" end

    if request.action == "package_update" then
        local args = { "update" }
        if request.package and request.package ~= "" then
            table.insert(args, tostring(request.package))
        end
        return launch("pkgctl.lua", "pkgctl", table.unpack(args))
    end

    if request.action == "package_configure" then
        if not request.package or request.package == "" then
            return false, "package required"
        end
        return launch("pkgctl.lua", "pkgctl", "configure", tostring(request.package))
    end

    return false, "unsupported admin action"
end

return M
