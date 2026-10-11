return {
    name = "remote-shell",
    description = "SSH-like remote administration shell",
    enabled = true,
    depends = { "network" },
    binary = "sshd.lua",
}
