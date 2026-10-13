return {
    name = "init",
    description = "Init service for CC Infrastructure startup",
    enabled = true,
    protected = true,
    modules = { "core", "init" },
    web = {
        visible = true,
        title = "Init",
        section = "system",
    },
}
