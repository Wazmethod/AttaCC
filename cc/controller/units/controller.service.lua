return {
    name = "controller",
    description = "Automation/state-machine execution and physical outputs",
    enabled = true,
    depends = { "network" },
    binary = "controllerd.lua",
}
