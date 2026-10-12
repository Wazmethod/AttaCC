return {
    format = 1,
    version = "0.26.1-dev",

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
                { src = "cc/shared/lib/paths.lua", dest = "lib/paths.lua" },
            },
        },

        ["runtime.service-runner"] = {
            kind = "runtime",
            description = "Generic service unit loader and binary launcher",
            depends = { "runtime.package-manager" },
            files = {
                { src = "cc/shared/lib/service_boot.lua", dest = "lib/service_boot.lua" },
                { src = "cc/shared/lib/modules.lua", dest = "lib/modules.lua" },
                { src = "cc/shared/servicerun.lua", dest = "servicerun.lua" },
                { src = "cc/shared/init.lua", dest = "init.lua" },
                { src = "cc/shared/units/init.service.lua", dest = "/usr/lib/infra/systemd/init.service.lua" },
                { src = "cc/shared/units/core.service.lua", dest = "/usr/lib/infra/systemd/core.service.lua" },
                { src = "cc/shared/units/network.service.lua", dest = "/usr/lib/infra/systemd/network.service.lua" },
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
                { src = "cc/shared/ps.lua", dest = "ps.lua" },
                { src = "cc/shared/startup/infra-completion.lua", dest = "startup/infra-completion.lua" },
            },
        },

        ["module.remote-shell"] = {
            kind = "module",
            description = "Remote shell protocol and transport capability",
            depends = { "runtime.package-manager" },
            files = {
                { src = "cc/shared/module-descriptors/core.remote-shell.mod.lua", dest = "/usr/lib/infra/modules/core.remote-shell.mod.lua" },
            },
        },

        ["service.remote-shell"] = {
            kind = "service",
            description = "Core SSH-like remote administration shell",
            depends = { "runtime.service-runner", "runtime.shell-tools", "module.remote-shell" },
            files = {
                { src = "cc/shared/ssh.lua", dest = "ssh.lua" },
                { src = "cc/shared/sshd.lua", dest = "sshd.lua" },
                { src = "cc/shared/units/remote-shell.service.lua", dest = "/usr/lib/infra/systemd/remote-shell.service.lua" },
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
                { src = "cc/master/units/storage.service.lua", dest = "/usr/lib/infra/systemd/storage.service.lua" },
                { src = "cc/shared/module-descriptors/network.storage.mod.lua", dest = "/usr/lib/infra/modules/network.storage.mod.lua" },
            },
        },

        ["module.console"] = {
            kind = "module",
            description = "Interactive CC: Terminals console capability",
            depends = { "runtime.shell-tools" },
            files = {
                { src = "cc/shared/console.lua", dest = "console.lua" },
                { src = "cc/shared/module-descriptors/core.console.mod.lua", dest = "/usr/lib/infra/modules/core.console.mod.lua" },
            },
        },

        ["module.display"] = {
            kind = "module",
            description = "Display API and view descriptor capability",
            depends = { "runtime.package-manager" },
            files = {
                { src = "cc/shared/lib/display_api.lua", dest = "lib/display_api.lua" },
                { src = "cc/shared/module-descriptors/core.display.mod.lua", dest = "/usr/lib/infra/modules/core.display.mod.lua" },
            },
        },

        ["service.display"] = {
            kind = "service",
            description = "Monitor/display runtime service",
            depends = { "runtime.service-runner", "runtime.shell-tools", "module.display" },
            configure = { program = "displayctl.lua", args = { "configure" } },
            files = {
                { src = "cc/shared/displayd.lua", dest = "displayd.lua" },
                { src = "cc/shared/displayctl.lua", dest = "displayctl.lua" },
                { src = "cc/shared/units/display.service.lua", dest = "/usr/lib/infra/systemd/display.service.lua" },
            },
        },

        ["module.steamplant"] = {
            kind = "module",
            description = "Create steam plant supervision and black-start module",
            depends = { "runtime.package-manager" },
            files = {
                { src = "cc/collector/modules/steamplant.lua", dest = "modules/steamplant.lua" },
                { src = "cc/collector/module-descriptors/steamplant.mod.lua", dest = "/usr/lib/infra/modules/steamplant.mod.lua" },
            },
        },

        ["preset.infrastructure-node"] = {
            kind = "preset",
            description = "Infrastructure node with collection, control and local display",
            depends = {
                "runtime.service-runner",
                "runtime.package-manager",
                "service.remote-shell",
                "service.shared-storage-client",
                "module.steamplant",
            },
            files = {
                { src = "cc/collector/main.lua", dest = "collectord.lua" },
                { src = "cc/collector/units/collector.service.lua", dest = "/usr/lib/infra/systemd/collector.service.lua" },
                { src = "cc/collector/systemctl.lua", dest = "systemctl.lua" },
                { src = "cc/collector/ioctl.lua", dest = "ioctl.lua" },
                { src = "cc/collector/profilectl.lua", dest = "profilectl.lua" },
                { src = "cc/collector/touchtest.lua", dest = "touchtest.lua" },
                { src = "cc/collector/machinectl.lua", dest = "machinectl.lua" },
                { src = "cc/shared/startup.lua", dest = "startup.lua" },
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
                { src = "cc/collector/module-descriptors/collector.display.mod.lua", dest = "/usr/lib/infra/modules/collector.display.mod.lua" },
            },
        },

        ["preset.automation-node"] = {
            kind = "preset",
            description = "Generic automation/controller node",
            depends = {
                "runtime.service-runner",
                "runtime.package-manager",
                "service.remote-shell",
                "service.shared-storage-client",
            },
            files = {
                { src = "cc/controller/main.lua", dest = "controllerd.lua" },
                { src = "cc/controller/units/controller.service.lua", dest = "/usr/lib/infra/systemd/controller.service.lua" },
                { src = "cc/controller/systemctl.lua", dest = "systemctl.lua" },
                { src = "cc/controller/ioctl.lua", dest = "ioctl.lua" },
                { src = "cc/controller/profilectl.lua", dest = "profilectl.lua" },
                { src = "cc/controller/machinectl.lua", dest = "machinectl.lua" },
                { src = "cc/shared/startup.lua", dest = "startup.lua" },
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
                "runtime.service-runner",
                "runtime.package-manager",
                "service.remote-shell",
                "service.shared-storage-client",
                "service.shared-storage-server",
                "service.display",
            },
            files = {
                { src = "cc/master/main.lua", dest = "supervisord.lua" },
                { src = "cc/master/units/supervisor.service.lua", dest = "/usr/lib/infra/systemd/supervisor.service.lua" },
                { src = "cc/master/systemctl.lua", dest = "systemctl.lua" },
                { src = "cc/master/profilectl.lua", dest = "profilectl.lua" },
                { src = "cc/master/machinectl.lua", dest = "machinectl.lua" },
                { src = "cc/shared/startup.lua", dest = "startup.lua" },
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
                { src = "cc/master/units/webbridge.service.lua", dest = "/usr/lib/infra/systemd/webbridge.service.lua" },
                { src = "cc/master/module-descriptors/client.master.mod.lua", dest = "/usr/lib/infra/modules/client.master.mod.lua" },
                { src = "cc/master/module-descriptors/web.bridge.mod.lua", dest = "/usr/lib/infra/modules/web.bridge.mod.lua" },
            },
        },

        ["preset.workstation"] = {
            kind = "preset",
            description = "Interactive operator/administration workstation",
            depends = {
                "module.console",
                "runtime.service-runner",
                "runtime.package-manager",
                "service.remote-shell",
                "service.shared-storage-client",
                "service.display",
            },
            files = {
                { src = "cc/workstation/main.lua", dest = "workstationd.lua" },
                { src = "cc/workstation/units/workstation.service.lua", dest = "/usr/lib/infra/systemd/workstation.service.lua" },
                { src = "cc/controller/systemctl.lua", dest = "systemctl.lua" },
                { src = "cc/workstation/profilectl.lua", dest = "profilectl.lua" },
                { src = "cc/controller/machinectl.lua", dest = "machinectl.lua" },
                { src = "cc/shared/startup.lua", dest = "startup.lua" },
                { src = "cc/workstation/lib/config.lua", dest = "lib/config.lua" },
                { src = "cc/workstation/lib/devices.lua", dest = "lib/devices.lua" },
                { src = "cc/workstation/module-descriptors/client.workstation.mod.lua", dest = "/usr/lib/infra/modules/client.workstation.mod.lua" },
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
                "runtime.service-runner",
                "runtime.package-manager",
                "service.remote-shell",
                "service.shared-storage-client",
            },
            files = {
                { src = "cc/pocket/main.lua", dest = "clientd.lua" },
                { src = "cc/pocket/units/client.service.lua", dest = "/usr/lib/infra/systemd/client.service.lua" },
                { src = "cc/pocket/systemctl.lua", dest = "systemctl.lua" },
                { src = "cc/pocket/profilectl.lua", dest = "profilectl.lua" },
                { src = "cc/pocket/machinectl.lua", dest = "machinectl.lua" },
                { src = "cc/shared/startup.lua", dest = "startup.lua" },
                { src = "cc/pocket/lib/config.lua", dest = "lib/config.lua" },
                { src = "cc/pocket/lib/runtime.lua", dest = "lib/runtime.lua" },
                { src = "cc/pocket/lib/services.lua", dest = "lib/services.lua" },
                { src = "cc/pocket/lib/protocol.lua", dest = "lib/protocol.lua" },
                { src = "cc/pocket/lib/machine.lua", dest = "lib/machine.lua" },
                { src = "cc/pocket/lib/nodes.lua", dest = "lib/nodes.lua" },
                { src = "cc/pocket/lib/ui.lua", dest = "lib/ui.lua" },
                { src = "cc/pocket/lib/display.lua", dest = "lib/display.lua" },
                { src = "cc/pocket/lib/ui_graphics.lua", dest = "lib/ui_graphics.lua" },
                { src = "cc/pocket/module-descriptors/client.pocket.mod.lua", dest = "/usr/lib/infra/modules/client.pocket.mod.lua" },
            },
        },
    },
}
