return {
    name = "collector",
    description = "Physical input collection and telemetry publication",
    enabled = true,
    depends = { "network" },
    binary = "collectord.lua",
    modules = { "steamplant" },
}
