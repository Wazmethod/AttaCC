return {
    format = 1,
    version = "0.29.0-dev",

    aliases = {
        collector = "preset.infrastructure-node",
        controller = "preset.automation-node",
        master = "preset.supervisor",
        pocket = "preset.portable-client",
        workstation = "preset.workstation",
        ["service.shared-storage-client"] = "module.storage-client",
        ["service.shared-storage-server"] = "module.storage-server",
        ["module.steamplant"] = "app.steamplant",
    },

    packages = {
        ["runtime.package-manager"] = {
            kind = "runtime",
            description = "Package manager bootstrap and installer",
            files = {
                { src = "pkgctl.lua", dest = "pkgctl.lua" },
                { src = "install.lua", dest = "install.lua" },
                { src = "cc/shared/lib/paths.lua", dest = "lib/paths.lua" },
                { src = "cc/shared/lib/migrations.lua", dest = "lib/migrations.lua" },
                { src = "cc/shared/migrate.lua", dest = "migrate.lua" },
            },
        },

        ["core.bus"] = {
            kind = "runtime",
            description = "Lightweight local AttaCC event bus",
            depends = { "runtime.package-manager" },
            files = {
                { src = "core/bus.lua", dest = "lib/bus.lua" },
            },
        },

        ["module.network"] = {
            kind = "module",
            description = "AttaCC modem transport and local bus bridge",
            depends = { "core.bus" },
            files = {
                { src = "modules/network.lua", dest = "lib/network.lua" },
            },
        },

        ["runtime.service-runner"] = {
            kind = "runtime",
            description = "Generic service unit loader and binary launcher",
            depends = { "runtime.package-manager" },
            files = {
                { src = "cc/shared/lib/service_boot.lua", dest = "lib/service_boot.lua" },
                { src = "cc/shared/lib/modules.lua", dest = "lib/modules.lua" },
                { src = "cc/shared/lib/system_snapshot.lua", dest = "lib/system_snapshot.lua" },
                { src = "cc/shared/lib/admin_control.lua", dest = "lib/admin_control.lua" },
                { src = "cc/shared/lib/webcap.lua", dest = "lib/webcap.lua" },
                { src = "cc/shared/servicerun.lua", dest = "servicerun.lua" },
                { src = "cc/shared/init.lua", dest = "init.lua" },
                { src = "cc/shared/units/init.service.lua", dest = "/usr/lib/systemd/init.service.lua" },
                { src = "cc/shared/units/core.service.lua", dest = "/usr/lib/systemd/core.service.lua" },
                { src = "cc/shared/units/network.service.lua", dest = "/usr/lib/systemd/network.service.lua" },
                { src = "cc/shared/module-descriptors/init.mod.lua", dest = "/usr/lib/modules/init.mod.lua" },
                { src = "cc/shared/module-descriptors/core.mod.lua", dest = "/usr/lib/modules/core.mod.lua" },
                { src = "cc/shared/module-descriptors/core.network.mod.lua", dest = "/usr/lib/modules/core.network.mod.lua" },
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
                { src = "cc/shared/module-descriptors/core.remote-shell.mod.lua", dest = "/usr/lib/modules/core.remote-shell.mod.lua" },
            },
        },

        ["service.remote-shell"] = {
            kind = "service",
            description = "Core SSH-like remote administration shell",
            depends = { "runtime.service-runner", "runtime.shell-tools", "module.remote-shell" },
            files = {
                { src = "cc/shared/ssh.lua", dest = "ssh.lua" },
                { src = "cc/shared/sshd.lua", dest = "sshd.lua" },
                { src = "cc/shared/units/remote-shell.service.lua", dest = "/usr/lib/systemd/remote-shell.service.lua" },
            },
        },

        ["module.storage-client"] = {
            kind = "module",
            description = "AttaCC shared storage client and CLI",
            depends = { "module.network" },
            files = {
                { src = "modules/storage/client.lua", dest = "lib/storage_client.lua" },
                { src = "modules/storage/storagectl.lua", dest = "storagectl.lua" },
            },
        },

        ["module.storage-server"] = {
            kind = "module",
            description = "Optional persistent shared key/value store host capability",
            depends = { "module.storage-client" },
            files = {
                { src = "modules/storage/backend.lua", dest = "lib/storage_backend.lua" },
                { src = "modules/storage/network_store.lua", dest = "lib/network_store.lua" },
                { src = "cc/shared/module-descriptors/network.storage.mod.lua", dest = "/usr/lib/modules/network.storage.mod.lua" },
            },
        },

        ["module.console"] = {
            kind = "module",
            description = "Interactive CC: Terminals console capability",
            depends = { "runtime.shell-tools" },
            files = {
                { src = "cc/shared/console.lua", dest = "console.lua" },
                { src = "cc/shared/module-descriptors/core.console.mod.lua", dest = "/usr/lib/modules/core.console.mod.lua" },
            },
        },

        ["module.display"] = {
            kind = "module",
            description = "Adaptive AttaCC display capability and pagination/layout helpers",
            depends = { "core.bus" },
            files = {
                { src = "modules/display.lua", dest = "lib/display.lua" },
                { src = "modules/display_api.lua", dest = "lib/display_api.lua" },
                { src = "cc/shared/module-descriptors/core.display.mod.lua", dest = "/usr/lib/modules/core.display.mod.lua" },
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
                { src = "cc/shared/units/display.service.lua", dest = "/usr/lib/systemd/display.service.lua" },
            },
        },

        ["app.steamplant"] = {
            kind = "app",
            description = "SteamPlant generator control application",
            depends = { "runtime.package-manager" },
            files = {
                { src = "apps/steamplant/app.lua", dest = "modules/steamplant.lua" },
                { src = "cc/collector/module-descriptors/steamplant.mod.lua", dest = "/usr/lib/modules/steamplant.mod.lua" },
            },
        },

        ["preset.infrastructure-node"] = {
            kind = "preset",
            description = "Infrastructure node with collection, control and local display",
            depends = {
                "runtime.service-runner",
                "runtime.package-manager",
                "module.network",
                "module.display",
                "app.steamplant",
            },
            files = {
                { src = "apps/steamplant/main.lua", dest = "collectord.lua" },
                { src = "cc/collector/units/collector.service.lua", dest = "/usr/lib/systemd/collector.service.lua" },
                { src = "apps/steamplant/tools/ioctl.lua", dest = "ioctl.lua" },
                { src = "apps/steamplant/tools/profilectl.lua", dest = "profilectl.lua" },
                { src = "apps/steamplant/tools/touchtest.lua", dest = "touchtest.lua" },
                { src = "apps/steamplant/tools/machinectl.lua", dest = "machinectl.lua" },
                { src = "core/startup.lua", dest = "startup.lua" },
                { src = "apps/steamplant/config.lua", dest = "lib/config.lua" },
                { src = "core/runtime.lua", dest = "lib/runtime.lua" },
                { src = "core/services.lua", dest = "lib/services.lua" },
                { src = "apps/steamplant/io_registry.lua", dest = "lib/io_registry.lua" },
                { src = "apps/steamplant/controller.lua", dest = "lib/controller.lua" },
                { src = "apps/steamplant/io.lua", dest = "lib/io.lua" },
                { src = "core/protocol.lua", dest = "lib/protocol.lua" },
                { src = "apps/steamplant/machine.lua", dest = "lib/machine.lua" },
                { src = "core/nodes.lua", dest = "lib/nodes.lua" },
                { src = "apps/steamplant/module_router.lua", dest = "lib/module_router.lua" },
                { src = "apps/steamplant/telemetry.lua", dest = "lib/telemetry.lua" },
                { src = "apps/steamplant/view.lua", dest = "lib/steamplant_display.lua" },
                { src = "apps/steamplant/view_text.lua", dest = "lib/ui.lua" },
                { src = "apps/steamplant/view_graphics.lua", dest = "lib/ui_graphics.lua" },
                { src = "cc/collector/module-descriptors/collector.display.mod.lua", dest = "/usr/lib/modules/collector.display.mod.lua" },
            },
        },

        ["preset.automation-node"] = {
            kind = "preset",
            description = "Generic automation/controller node",
            depends = {
                "runtime.service-runner",
                "runtime.package-manager",
                "module.network",
                "module.display",
            },
            files = {
                { src = "cc/controller/main.lua", dest = "controllerd.lua" },
                { src = "cc/controller/units/controller.service.lua", dest = "/usr/lib/systemd/controller.service.lua" },
                { src = "cc/controller/ioctl.lua", dest = "ioctl.lua" },
                { src = "cc/controller/profilectl.lua", dest = "profilectl.lua" },
                { src = "cc/controller/machinectl.lua", dest = "machinectl.lua" },
                { src = "core/startup.lua", dest = "startup.lua" },
                { src = "cc/controller/lib/config.lua", dest = "lib/config.lua" },
                { src = "core/runtime.lua", dest = "lib/runtime.lua" },
                { src = "core/services.lua", dest = "lib/services.lua" },
                { src = "cc/controller/lib/io_registry.lua", dest = "lib/io_registry.lua" },
                { src = "core/protocol.lua", dest = "lib/protocol.lua" },
                { src = "cc/controller/lib/machine.lua", dest = "lib/machine.lua" },
                { src = "core/nodes.lua", dest = "lib/nodes.lua" },
                { src = "cc/controller/lib/module_router.lua", dest = "lib/module_router.lua" },
            },
        },

        ["preset.supervisor"] = {
            kind = "preset",
            description = "AttaCC master with native network, adaptive display and optional capabilities",
            depends = {
                "runtime.service-runner",
                "runtime.package-manager",
                "module.network",
                "module.display",
            },
            files = {
                { src = "apps/master/main.lua", dest = "supervisord.lua" },
                { src = "apps/master/tools/profilectl.lua", dest = "profilectl.lua" },
                { src = "apps/master/tools/machinectl.lua", dest = "machinectl.lua" },
                { src = "core/startup.lua", dest = "startup.lua" },
                { src = "apps/master/config.lua", dest = "lib/config.lua" },
                { src = "core/runtime.lua", dest = "lib/runtime.lua" },
                { src = "core/services.lua", dest = "lib/services.lua" },
                { src = "core/protocol.lua", dest = "lib/protocol.lua" },
                { src = "apps/master/machine.lua", dest = "lib/machine.lua" },
                { src = "core/nodes.lua", dest = "lib/nodes.lua" },
                { src = "apps/master/view_text.lua", dest = "lib/ui.lua" },
                { src = "apps/master/view.lua", dest = "lib/master_display.lua" },
                { src = "apps/master/view_graphics.lua", dest = "lib/ui_graphics.lua" },
                { src = "apps/master/webbridge.lua", dest = "webbridge.lua" },
                { src = "apps/master/web.example.lua", dest = "web.example.lua" },
                { src = "cc/master/module-descriptors/client.master.mod.lua", dest = "/usr/lib/modules/client.master.mod.lua" },
                { src = "cc/master/module-descriptors/web.bridge.mod.lua", dest = "/usr/lib/modules/web.bridge.mod.lua" },
            },
        },

        ["preset.workstation"] = {
            kind = "preset",
            description = "Interactive operator/administration workstation",
            depends = {
                "module.console",
                "runtime.service-runner",
                "runtime.package-manager",
                "module.storage-client",
                "module.network",
                "module.display",
            },
            files = {
                { src = "apps/workstation/main.lua", dest = "workstationd.lua" },
                { src = "cc/workstation/units/workstation.service.lua", dest = "/usr/lib/systemd/workstation.service.lua" },
                { src = "apps/workstation/tools/profilectl.lua", dest = "profilectl.lua" },
                { src = "cc/controller/machinectl.lua", dest = "machinectl.lua" },
                { src = "core/startup.lua", dest = "startup.lua" },
                { src = "apps/workstation/config.lua", dest = "lib/config.lua" },
                { src = "apps/workstation/devices.lua", dest = "lib/devices.lua" },
                { src = "cc/workstation/module-descriptors/client.workstation.mod.lua", dest = "/usr/lib/modules/client.workstation.mod.lua" },
                { src = "core/runtime.lua", dest = "lib/runtime.lua" },
                { src = "core/services.lua", dest = "lib/services.lua" },
                { src = "core/protocol.lua", dest = "lib/protocol.lua" },
                { src = "cc/controller/lib/machine.lua", dest = "lib/machine.lua" },
                { src = "core/nodes.lua", dest = "lib/nodes.lua" },
            },
        },

        ["preset.portable-client"] = {
            kind = "preset",
            description = "AttaCC portable client with native network and optional external display",
            depends = {
                "runtime.service-runner",
                "runtime.package-manager",
                "module.network",
                "module.display",
            },
            files = {
                { src = "apps/pocket/main.lua", dest = "clientd.lua" },
                { src = "cc/pocket/units/client.service.lua", dest = "/usr/lib/systemd/client.service.lua" },
                { src = "apps/pocket/tools/profilectl.lua", dest = "profilectl.lua" },
                { src = "apps/pocket/tools/machinectl.lua", dest = "machinectl.lua" },
                { src = "core/startup.lua", dest = "startup.lua" },
                { src = "apps/pocket/config.lua", dest = "lib/config.lua" },
                { src = "core/runtime.lua", dest = "lib/runtime.lua" },
                { src = "core/services.lua", dest = "lib/services.lua" },
                { src = "core/protocol.lua", dest = "lib/protocol.lua" },
                { src = "apps/pocket/machine.lua", dest = "lib/machine.lua" },
                { src = "core/nodes.lua", dest = "lib/nodes.lua" },
                { src = "apps/pocket/view_text.lua", dest = "lib/ui.lua" },
                { src = "apps/pocket/view.lua", dest = "lib/pocket_display.lua" },
                { src = "apps/pocket/view_graphics.lua", dest = "lib/ui_graphics.lua" },
                { src = "cc/pocket/module-descriptors/client.pocket.mod.lua", dest = "/usr/lib/modules/client.pocket.mod.lua" },
            },
        },
    },
}
