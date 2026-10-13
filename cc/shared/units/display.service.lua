return {
    name = "display",
    description = "Local monitor/display runtime",
    enabled = true,
    depends = { "core" },
    binary = "displayd.lua",
    modules = { "core.display" },
    web = {
        visible = true,
        title = "Display",
        section = "interface",
        exports = { "monitor", "owner", "view", "views" },
        commands = {
            { id = "demo", label = "Demo", program = "displayctl.lua", args = { "demo" } },
            { id = "clear", label = "Clear view", program = "displayctl.lua", args = { "clear" }, confirm = true },
        },
    },
}
