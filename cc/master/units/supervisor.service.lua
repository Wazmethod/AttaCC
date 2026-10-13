return {
    name = "supervisor",
    description = "Network supervision and wall dashboard aggregation",
    enabled = true,
    depends = { "network" },
    binary = "supervisord.lua",
    modules = { "client.master", "core.display" },
    web = {
        visible = true,
        title = "Supervisor",
        section = "system",
    },
}
