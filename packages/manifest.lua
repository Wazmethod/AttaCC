return {
    format = 1,
    version = "0.25.0-dev",

    aliases = {
        collector = "preset.infrastructure-node",
        controller = "preset.automation-node",
        master = "preset.supervisor",
        pocket = "preset.portable-client",
        workstation = "preset.workstation",
    },

    packages = {
        ["runtime.package-manager"] = {
            kind = "runtime",
            description = "Package manager bootstrap and installer",
            files = {
                { src = "pkgctl.lua", dest = "pkgctl.lua" },
                { src = "install.lua", dest = "install.lua" },
            },
        },

        ["runtime.shell-tools"] = {
            kind = "runtime",
            description = "Infrastructure shell environment, completion and pager",
            depends = { "runtime.package-manager" },
            files = {
                { src = "cc/shared/less.lua", dest = "less.lua" },
                { src = "cc/shared/cat.lua", dest = "cat.lua" },
                { src = "cc/shared/lsmod.lua", dest = "lsmod.lua" },
                { src = "cc/shared/console.lua", dest = "console.lua" },
                { src = "cc/shared/startup/infra-completion.lua", dest = "startup/infra-completion.lua" },
            },
        },

        ["service.remote-shell"] = {
            kind = "service",
            description = "Core SSH-like remote administration shell",
            depends = { "runtime.shell-tools" },
            files = {
                { src = "cc/shared/ssh.lua", dest = "ssh.lua" },
                { src = "cc/shared/sshd.lua", dest = "sshd.lua" },
            },
        },

        ["service.shared-storage-client"] = {
            kind = "service",
            description = "Client library and CLI for the network shared store",
            depends = { "runtime.package-manager" },
            files = {
                { src = "cc/shared/lib/storage_client.lua", dest = "lib/storage_client.lua" },
                { src = "cc/shared/storagectl.lua", dest = "storagectl.lua" },
            },
        },

        ["service.shared-storage-server"] = {
            kind = "service",
            description = "Master-side persistent shared key/value store",
            depends = { "service.shared-storage-client" },
            files = {
                { src = "cc/master/lib/network_store.lua", dest = "lib/network_store.lua" },
            },
        },

        ["module.display"] = {
            kind = "module",
            description = "Standalone profile-aware infrastructure display",
            depends = { "runtime.package-manager" },
            files = {
                { src = "cc/shared/displayd.lua", dest = "displayd.lua" },
            },
        },

        ["module.steamplant"] = {
            kind = "module",
            description = "Create steam plant supervision and black-start module",
            depends = { "runtime.package-manager" },
            files = {
                { src = "cc/collector/modules/steamplant.lua", dest = "modules/steamplant.lua" },
            },
        },

        ["preset.infrastructure-node"] = {
            kind = "preset",
            description = "Infrastructure node with collection, control and local display",
            depends = {
                "runtime.package-manager",
                "service.remote-shell",
                "service.shared-storage-client",
                "module.steamplant",
            },
            files = {
                { src = "cc/collector/main.lua", dest = "main.lua" },
                { src = "cc/collector/systemctl.lua", dest = "systemctl.lua" },
                { src = "cc/collector/ioctl.lua", dest = "ioctl.lua" },
                { src = "cc/collector/profilectl.lua", dest = "profilectl.lua" },
                { src = "cc/collector/touchtest.lua", dest = "touchtest.lua" },
                { src = "cc/collector/machinectl.lua", dest = "machinectl.lua" },
                { src = "cc/collector/startup.lua", dest = "startup.lua" },
                { src = "cc/collector/lib/config.lua", dest = "lib/config.lua" },
                { src = "cc/collector/lib/runtime.lua", dest = "lib/runtime.lua" },
                { src = "cc/collector/lib/services.lua", dest = "lib/services.lua" },
                { src = "cc/collector/lib/io_registry.lua", dest = "lib/io_registry.lua" },
                { src = "cc/collector/lib/controller.lua", dest = "lib/controller.lua" },
                { src = "cc/collector/lib/io.lua", dest = "lib/io.lua" },
                { src = "cc/collector/lib/protocol.lua", dest = "lib/protocol.lua" },
                { src = "cc/collector/lib/machine.lua", dest = "lib/machine.lua" },
                { src = "cc/collector/lib/nodes.lua", dest = "lib/nodes.lua" },
                { src = "cc/collector/lib/module_router.lua", dest = "lib/module_router.lua" },
                { src = "cc/collector/lib/telemetry.lua", dest = "lib/telemetry.lua" },
                { src = "cc/collector/lib/display.lua", dest = "lib/display.lua" },
                { src = "cc/collector/lib/ui.lua", dest = "lib/ui.lua" },
                { src = "cc/collector/lib/ui_graphics.lua", dest = "lib/ui_graphics.lua" },
            },
        },

        ["preset.automation-node"] = {
            kind = "preset",
            description = "Generic automation/controller node",
            depends = {
                "runtime.package-manager",
                "service.remote-shell",
                "service.shared-storage-client",
            },
            files = {
                { src = "cc/controller/main.lua", dest = "main.lua" },
                { src = "cc/controller/systemctl.lua", dest = "systemctl.lua" },
                { src = "cc/controller/ioctl.lua", dest = "ioctl.lua" },
                { src = "cc/controller/profilectl.lua", dest = "profilectl.lua" },
                { src = "cc/controller/machinectl.lua", dest = "machinectl.lua" },
                { src = "cc/controller/startup.lua", dest = "startup.lua" },
                { src = "cc/controller/lib/config.lua", dest = "lib/config.lua" },
                { src = "cc/controller/lib/runtime.lua", dest = "lib/runtime.lua" },
                { src = "cc/controller/lib/services.lua", dest = "lib/services.lua" },
                { src = "cc/controller/lib/io_registry.lua", dest = "lib/io_registry.lua" },
                { src = "cc/controller/lib/protocol.lua", dest = "lib/protocol.lua" },
                { src = "cc/controller/lib/machine.lua", dest = "lib/machine.lua" },
                { src = "cc/controller/lib/nodes.lua", dest = "lib/nodes.lua" },
                { src = "cc/controller/lib/module_router.lua", dest = "lib/module_router.lua" },
            },
        },

        ["preset.supervisor"] = {
            kind = "preset",
            description = "Supervisor/master node with wall UI, web bridge and shared storage",
            depends = {
                "runtime.package-manager",
                "service.remote-shell",
                "service.shared-storage-client",
                "service.shared-storage-server",
            },
            files = {
                { src = "cc/master/main.lua", dest = "main.lua" },
                { src = "cc/master/systemctl.lua", dest = "systemctl.lua" },
                { src = "cc/master/profilectl.lua", dest = "profilectl.lua" },
                { src = "cc/master/machinectl.lua", dest = "machinectl.lua" },
                { src = "cc/master/startup.lua", dest = "startup.lua" },
                { src = "cc/master/lib/config.lua", dest = "lib/config.lua" },
                { src = "cc/master/lib/runtime.lua", dest = "lib/runtime.lua" },
                { src = "cc/master/lib/services.lua", dest = "lib/services.lua" },
                { src = "cc/master/lib/protocol.lua", dest = "lib/protocol.lua" },
                { src = "cc/master/lib/machine.lua", dest = "lib/machine.lua" },
                { src = "cc/master/lib/nodes.lua", dest = "lib/nodes.lua" },
                { src = "cc/master/lib/ui.lua", dest = "lib/ui.lua" },
                { src = "cc/master/lib/display.lua", dest = "lib/display.lua" },
                { src = "cc/master/lib/ui_graphics.lua", dest = "lib/ui_graphics.lua" },
                { src = "cc/master/webbridge.lua", dest = "webbridge.lua" },
                { src = "cc/master/web.example.lua", dest = "web.example.lua" },
            },
        },

        ["preset.workstation"] = {
            kind = "preset",
            description = "Interactive operator/administration workstation",
            depends = {
                "runtime.package-manager",
                "service.remote-shell",
                "service.shared-storage-client",
                "module.display",
            },
            files = {
                { src = "cc/workstation/main.lua", dest = "main.lua" },
                { src = "cc/controller/systemctl.lua", dest = "systemctl.lua" },
                { src = "cc/workstation/profilectl.lua", dest = "profilectl.lua" },
                { src = "cc/controller/machinectl.lua", dest = "machinectl.lua" },
                { src = "cc/workstation/startup.lua", dest = "startup.lua" },
                { src = "cc/workstation/lib/config.lua", dest = "lib/config.lua" },
                { src = "cc/workstation/lib/devices.lua", dest = "lib/devices.lua" },
                { src = "cc/controller/lib/runtime.lua", dest = "lib/runtime.lua" },
                { src = "cc/controller/lib/services.lua", dest = "lib/services.lua" },
                { src = "cc/controller/lib/protocol.lua", dest = "lib/protocol.lua" },
                { src = "cc/controller/lib/machine.lua", dest = "lib/machine.lua" },
                { src = "cc/controller/lib/nodes.lua", dest = "lib/nodes.lua" },
            },
        },

        ["preset.portable-client"] = {
            kind = "preset",
            description = "Portable Pocket client",
            depends = {
                "runtime.package-manager",
                "service.remote-shell",
                "service.shared-storage-client",
            },
            files = {
                { src = "cc/pocket/main.lua", dest = "main.lua" },
                { src = "cc/pocket/systemctl.lua", dest = "systemctl.lua" },
                { src = "cc/pocket/profilectl.lua", dest = "profilectl.lua" },
                { src = "cc/pocket/machinectl.lua", dest = "machinectl.lua" },
                { src = "cc/pocket/startup.lua", dest = "startup.lua" },
                { src = "cc/pocket/lib/config.lua", dest = "lib/config.lua" },
                { src = "cc/pocket/lib/runtime.lua", dest = "lib/runtime.lua" },
                { src = "cc/pocket/lib/services.lua", dest = "lib/services.lua" },
                { src = "cc/pocket/lib/protocol.lua", dest = "lib/protocol.lua" },
                { src = "cc/pocket/lib/machine.lua", dest = "lib/machine.lua" },
                { src = "cc/pocket/lib/nodes.lua", dest = "lib/nodes.lua" },
                { src = "cc/pocket/lib/ui.lua", dest = "lib/ui.lua" },
                { src = "cc/pocket/lib/display.lua", dest = "lib/display.lua" },
                { src = "cc/pocket/lib/ui_graphics.lua", dest = "lib/ui_graphics.lua" },
            },
        },
    },
}
