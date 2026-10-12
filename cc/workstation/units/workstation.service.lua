return {
    name = "workstation",
    description = "Interactive operator and administration workstation",
    enabled = true,
    depends = { "network" },
    binary = "workstationd.lua",
    modules = { "client.workstation" },
}
