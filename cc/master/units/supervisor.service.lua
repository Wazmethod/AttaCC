return {
    name = "supervisor",
    description = "Network supervision and wall dashboard aggregation",
    enabled = true,
    depends = { "network", "display" },
    binary = "supervisord.lua",
    modules = { "client.master", "core.display" },
}
