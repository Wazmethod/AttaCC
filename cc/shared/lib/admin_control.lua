local services = require("lib.services")
local serviceBoot = require("lib.service_boot")

local M = {}

local function launch(program, title, ...)
    if multishell and shell.openTab then
        local id = shell.openTab(program, ...)
        if id and title and multishell.setTitle then pcall(multishell.setTitle, id, title) end
        return true, { pid = id, started = true }
    end

    local ok = shell.run(program, ...)
    return ok ~= false, { started = true, synchronous = true }
end

local function unitCommand(serviceName, command)
    local service = services.status(serviceName)
    if not service then return false, "unknown service" end
    if command == "start" or command == "stop" or command == "restart"
        or command == "enable" or command == "disable"
    then
        local ok, result = launch("systemctl.lua", "systemctl", command, serviceName)
        if not ok then return false, "systemctl command failed" end
        return true, result
    end
    return false, "unsupported service action"
end

local function customServiceCommand(serviceName, commandId, suppliedArgs)
    local service = services.status(serviceName)
    if not service then return false, "unknown service" end
    local web = service.web
    if type(web) ~= "table" then return false, "service has no web capability" end

    local selected = nil
    for _, command in ipairs(web.commands or {}) do
        if type(command) == "table" and tostring(command.id) == tostring(commandId) then
            selected = command
            break
        end
    end
    if not selected then return false, "unknown exported command" end
    if not selected.program then return false, "command has no program" end

    local args = {}
    for _, value in ipairs(selected.args or {}) do table.insert(args, tostring(value)) end

    if selected.allowArgs == true and type(suppliedArgs) == "table" then
        for _, key in ipairs(selected.argOrder or {}) do
            if suppliedArgs[key] ~= nil then table.insert(args, tostring(suppliedArgs[key])) end
        end
    end

    return launch(selected.program, fs.getName(selected.program):gsub("%.lua$", ""), table.unpack(args))
end

function M.handle(request)
    if type(request) ~= "table" then return false, "invalid request" end

    local action = request.action
    if action == "service" then
        return unitCommand(tostring(request.service or ""), tostring(request.command or ""))
    elseif action == "service_command" then
        return customServiceCommand(
            tostring(request.service or ""),
            tostring(request.command or ""),
            request.args
        )
    elseif action == "package_update" then
        local args = { "update" }
        if request.package and request.package ~= "" then table.insert(args, tostring(request.package)) end
        return launch("pkgctl.lua", "pkgctl", table.unpack(args))
    elseif action == "package_configure" then
        if not request.package or request.package == "" then return false, "package required" end
        return launch("pkgctl.lua", "pkgctl", "configure", tostring(request.package))
    end

    return false, "unsupported admin action"
end

return M
