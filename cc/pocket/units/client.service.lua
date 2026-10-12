return {
    name = "client",
    description = "Portable infrastructure client",
    enabled = true,
    depends = { "network" },
    binary = "clientd.lua",
    modules = { "client.pocket" },
}
