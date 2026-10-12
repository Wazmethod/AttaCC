return {
    name = "core.remote-shell",
    description = "Remote shell protocol and interactive transport capability",
    requires = { "remote-shell.service" },
    requiresFiles = { "ssh.lua", "sshd.lua" },
}
