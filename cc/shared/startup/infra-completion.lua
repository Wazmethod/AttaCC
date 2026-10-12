-- CC Infrastructure shell environment
settings.set("motd.enable", false)
pcall(settings.save)

local completion = require("cc.shell.completion")

local function choices(values)
    return completion.build({ completion.choice, values })
end

local function serviceNames()
    local ok, services = pcall(require, "lib.services")
    local out = {}
    if ok and services and type(services.names) == "function" then
        for _, name in ipairs(services.names()) do
            table.insert(out, name .. ".service")
        end
    end
    table.sort(out)
    return out
end

local function cachedHostnames()
    local path = "/var/lib/infra/runtime/hosts.json"
    local out = {}
    if fs.exists(path) then
        local h = fs.open(path, "r")
        if h then
            local raw = h.readAll()
            h.close()
            local ok, data = pcall(textutils.unserializeJSON, raw)
            if ok and type(data) == "table" and type(data.hosts) == "table" then
                for hostname in pairs(data.hosts) do table.insert(out, hostname) end
                table.sort(out)
            end
        end
    end
    return out
end

local function register(program, fn)
    if fs.exists(program) then
        shell.setCompletionFunction(program, fn)
    end
end

-- Explicit aliases make our administration commands first-class shell programs.
for alias, program in pairs({
    machinectl = "machinectl.lua",
    profilectl = "profilectl.lua",
    systemctl = "systemctl.lua",
    pkgctl = "pkgctl.lua",
    storagectl = "storagectl.lua",
    displayctl = "displayctl.lua",
    ssh = "ssh.lua",
    less = "less.lua",
    cat = "cat.lua",
    lsmod = "lsmod.lua",
    ps = "ps.lua",
    console = "console.lua",
}) do
    if fs.exists(program) then shell.setAlias(alias, program) end
end

register("machinectl.lua", choices({
    "status", "version", "init", "hostname", "export", "import", "reset",
}))
register("profilectl.lua", choices({
    "status", "init", "edit", "reset",
}))
register("pkgctl.lua", choices({
    "list", "status", "show", "deps", "install", "update", "upgrade", "configure",
}))
register("storagectl.lua", choices({
    "ping", "get", "set", "delete", "list", "ns", "namespaces",
}))
register("displayctl.lua", choices({
    "configure", "status", "detect", "use", "views", "select", "demo", "clear",
}))

register("systemctl.lua", function(shellApi, index, argument, previous)
    if index == 1 then
        return require("cc.completion").choice(argument, {
            "list", "status", "logs", "start", "stop", "restart",
            "enable", "disable", "is-enabled", "dependencies",
            "cat", "edit", "daemon-reload", "config", "profile",
        }, true)
    elseif index == 2 then
        local cmd = previous[1]
        if cmd == "status" or cmd == "logs" or cmd == "start" or cmd == "stop"
            or cmd == "restart" or cmd == "enable" or cmd == "disable"
            or cmd == "is-enabled" or cmd == "dependencies"
            or cmd == "cat" or cmd == "edit"
        then
            return require("cc.completion").choice(argument, serviceNames(), true)
        end
    end
end)

register("ssh.lua", function(shellApi, index, argument)
    if index == 1 then
        local values = { "--scan", "--sync" }
        for _, hostname in ipairs(cachedHostnames()) do table.insert(values, hostname) end
        return require("cc.completion").choice(argument, values, true)
    end
end)
