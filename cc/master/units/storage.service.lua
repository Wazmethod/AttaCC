return {
    name = "storage",
    description = "Persistent network shared key/value store",
    enabled = true,
    depends = { "network" },
    binary = "supervisord.lua",
    modules = { "network.storage" },
}
