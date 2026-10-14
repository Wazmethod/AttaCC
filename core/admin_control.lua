local M = {}

local function launch(program, title, rebootOnSuccess, ...)
    local args = { ... }

    if multishell and multishell.launch then
        local env = {}
        setmetatable(env, { __index = _ENV })

        local runnerArgs = {}
        if rebootOnSuccess then table.insert(runnerArgs, "--reboot-success") end
        table.insert(runnerArgs, program)
        for _, arg in ipairs(args) do table.insert(runnerArgs, arg) end

        local id = multishell.launch(env, "runonce.lua", table.unpack(runnerArgs))
        if id and title and multishell.setTitle then
            pcall(multishell.setTitle, id, title)
        end
        return true, { pid = id, started = true, autoClose = true, rebootOnSuccess = rebootOnSuccess }
    end

    local ok = shell.run(program, table.unpack(args))
    if ok ~= false and rebootOnSuccess then
        sleep(0.5)
        os.reboot()
    end
    return ok ~= false, { started = true, synchronous = true, rebootOnSuccess = rebootOnSuccess }
end

function M.handle(request)
    if type(request) ~= "table" then return false, "invalid request" end

    if request.action == "package_update" then
        local args = { "update" }
        if request.package and request.package ~= "" then
            table.insert(args, tostring(request.package))
        end
        return launch("pkgctl.lua", "pkgctl-update", true, table.unpack(args))
    end

    if request.action == "package_configure" then
        if not request.package or request.package == "" then
            return false, "package required"
        end
        return launch("pkgctl.lua", "pkgctl-config", false, "configure", tostring(request.package))
    end

    return false, "unsupported admin action"
end

return M
