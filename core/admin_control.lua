local M = {}

local function launch(program, title, ...)
    if multishell and shell.openTab then
        local id = shell.openTab(program, ...)
        if id and title and multishell.setTitle then
            pcall(multishell.setTitle, id, title)
        end
        return true, { pid = id, started = true }
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

    if request.action == "service" or request.action == "service_command" then
        return false, "legacy service control was removed from AttaCC"
    end

    return false, "unsupported admin action"
end

return M
