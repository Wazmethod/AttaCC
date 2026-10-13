return {
    name = "remote-shell",
    description = "SSH-like remote administration shell",
    enabled = true,
    depends = { "network" },
    binary = "sshd.lua",
    modules = { "core.remote-shell" },
    web = {
        visible = true,
        title = "Remote shell",
        section = "access",
    },
}
