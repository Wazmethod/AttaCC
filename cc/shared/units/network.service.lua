return {
    name = "network",
    description = "Logical network and message transport",
    enabled = true,
    protected = true,
    depends = { "core" },
    modules = { "core.network" },
}
