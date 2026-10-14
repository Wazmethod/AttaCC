return {
    format = 2,
    version = "0.31.0-dev",

    aliases = {
        steamplant = "preset.steamplant",
        master = "preset.master",
        pocket = "preset.pocket",
        workstation = "preset.workstation",
        dashboard = "preset.dashboard",
    },

    packages = {
        ["runtime.package-manager"] = {
            kind = "runtime",
            description = "AttaCC package manager bootstrap",
            files = {
                { src = "pkgctl.lua", dest = "pkgctl.lua" },
                { src = "install.lua", dest = "install.lua" },
            },
        },

        ["core.runtime"] = {
            kind = "core",
            description = "Native AttaCC runtime, local bus, discovery and administration primitives",
            depends = { "runtime.package-manager" },
            files = {
                { src = "core/paths.lua", dest = "lib/paths.lua" },
                { src = "core/runtime.lua", dest = "lib/runtime.lua" },
                { src = "core/bus.lua", dest = "lib/bus.lua" },
                { src = "core/protocol.lua", dest = "lib/protocol.lua" },
                { src = "core/machine.lua", dest = "lib/machine.lua" },
                { src = "core/profile_store.lua", dest = "lib/profile_store.lua" },
                { src = "core/nodes.lua", dest = "lib/nodes.lua" },
                { src = "core/module_router.lua", dest = "lib/module_router.lua" },
                { src = "core/io_registry.lua", dest = "lib/io_registry.lua" },
                { src = "core/tools/machinectl.lua", dest = "machinectl.lua" },
                { src = "core/tools/ioctl.lua", dest = "ioctl.lua" },
                { src = "core/runonce.lua", dest = "runonce.lua" },
                { src = "core/system_snapshot.lua", dest = "lib/system_snapshot.lua" },
                { src = "core/admin_control.lua", dest = "lib/admin_control.lua" },
                { src = "core/webcap.lua", dest = "lib/webcap.lua" },
                { src = "core/startup.lua", dest = "startup.lua" },
            },
        },

        ["module.network"] = {
            kind = "module",
            description = "AttaCC modem transport and local bus bridge",
            depends = { "core.runtime" },
            files = {
                { src = "modules/network.lua", dest = "lib/network.lua" },
            },
        },

        ["module.ui-pages"] = {
            kind = "module",
            description = "Generic AttaCC UI descriptor pagination",
            depends = { "core.runtime" },
            files = {
                { src = "modules/ui_pages.lua", dest = "lib/ui_pages.lua" },
            },
        },

        ["module.dashboard"] = {
            kind = "module",
            description = "Generic AttaCC dashboard model and categorized machine pagination",
            depends = { "module.ui-pages" },
            files = {
                { src = "modules/dashboard.lua", dest = "lib/dashboard.lua" },
                { src = "modules/dashboard_view_text.lua", dest = "lib/dashboard_view_text.lua" },
                { src = "modules/dashboard_view_graphics.lua", dest = "lib/dashboard_view_graphics.lua" },
            },
        },

        ["module.display"] = {
            kind = "module",
            description = "Adaptive optional display capability",
            depends = { "core.runtime", "module.ui-pages", "module.dashboard" },
            files = {
                { src = "modules/display.lua", dest = "lib/display.lua" },
                { src = "modules/display_graphics.lua", dest = "lib/display_graphics.lua" },
                { src = "modules/display_api.lua", dest = "lib/display_api.lua" },
            },
        },

        ["module.storage-client"] = {
            kind = "module",
            description = "Shared storage client and CLI",
            depends = { "module.network" },
            files = {
                { src = "modules/storage/client.lua", dest = "lib/storage_client.lua" },
                { src = "modules/storage/storagectl.lua", dest = "storagectl.lua" },
            },
        },

        ["module.storage-server"] = {
            kind = "module",
            description = "Optional persistent shared storage host",
            depends = { "module.storage-client" },
            files = {
                { src = "modules/storage/backend.lua", dest = "lib/storage_backend.lua" },
                { src = "modules/storage/network_store.lua", dest = "lib/network_store.lua" },
                { src = "modules/storage/host.lua", dest = "storagehost.lua" },
            },
        },

        ["app.steamplant"] = {
            kind = "app",
            description = "SteamPlant generator control application",
            depends = { "module.network", "module.display" },
            files = {
                { src = "apps/steamplant/main.lua", dest = "steamplant.lua" },
                { src = "apps/steamplant/config.lua", dest = "lib/config.lua" },
                { src = "apps/steamplant/app.lua", dest = "modules/steamplant.lua" },
                { src = "apps/steamplant/controller.lua", dest = "lib/controller.lua" },
                { src = "apps/steamplant/io.lua", dest = "lib/io.lua" },
                { src = "apps/steamplant/telemetry.lua", dest = "lib/telemetry.lua" },
                { src = "apps/steamplant/view.lua", dest = "lib/steamplant_display.lua" },
                { src = "apps/steamplant/view_text.lua", dest = "lib/ui.lua" },
                { src = "apps/steamplant/view_graphics.lua", dest = "lib/ui_graphics.lua" },
                { src = "apps/steamplant/tools/profilectl.lua", dest = "profilectl.lua" },
                { src = "apps/steamplant/tools/touchtest.lua", dest = "touchtest.lua" },
            },
        },

        ["app.master"] = {
            kind = "app",
            description = "AttaCC supervision, aggregation and optional Web bridge",
            depends = { "module.network", "module.display" },
            files = {
                { src = "apps/master/main.lua", dest = "master.lua" },
                { src = "apps/master/config.lua", dest = "lib/config.lua" },
                { src = "apps/master/view.lua", dest = "lib/master_display.lua" },
                { src = "apps/master/webbridge.lua", dest = "webbridge.lua" },
                { src = "apps/master/web.example.lua", dest = "web.example.lua" },
                { src = "apps/master/tools/profilectl.lua", dest = "profilectl.lua" },
                { src = "apps/master/tools/webbridgectl.lua", dest = "webbridgectl.lua" },
            },
        },

        ["app.pocket"] = {
            kind = "app",
            description = "Portable generic AttaCC control client",
            depends = { "module.network", "module.display" },
            files = {
                { src = "apps/pocket/main.lua", dest = "pocket.lua" },
                { src = "apps/pocket/config.lua", dest = "lib/config.lua" },
                { src = "apps/pocket/view.lua", dest = "lib/pocket_display.lua" },
                { src = "apps/pocket/pages.lua", dest = "lib/pocket_pages.lua" },
                { src = "apps/pocket/view_text.lua", dest = "lib/ui.lua" },
                { src = "apps/pocket/view_graphics.lua", dest = "lib/ui_graphics.lua" },
                { src = "apps/pocket/tools/profilectl.lua", dest = "profilectl.lua" },
            },
        },

        ["app.workstation"] = {
            kind = "app",
            description = "Interactive AttaCC operator workstation",
            depends = { "module.network", "module.display", "module.storage-client" },
            files = {
                { src = "apps/workstation/main.lua", dest = "workstation.lua" },
                { src = "apps/workstation/config.lua", dest = "lib/config.lua" },
                { src = "apps/workstation/devices.lua", dest = "lib/devices.lua" },
                { src = "apps/workstation/tools/profilectl.lua", dest = "profilectl.lua" },
            },
        },

        ["app.dashboard"] = {
            kind = "app",
            description = "Dedicated AttaCC network dashboard and control display",
            depends = { "module.network", "module.display" },
            files = {
                { src = "apps/dashboard/main.lua", dest = "dashboard.lua" },
                { src = "apps/dashboard/config.lua", dest = "lib/config.lua" },
                { src = "apps/dashboard/view.lua", dest = "lib/dashboard_display.lua" },
                { src = "apps/dashboard/tools/profilectl.lua", dest = "profilectl.lua" },
            },
        },

        ["preset.steamplant"] = {
            kind = "preset",
            description = "SteamPlant generator node",
            depends = { "app.steamplant" },
            files = {},
        },

        ["preset.master"] = {
            kind = "preset",
            description = "AttaCC master node",
            depends = { "app.master" },
            files = {},
        },

        ["preset.pocket"] = {
            kind = "preset",
            description = "AttaCC Pocket client",
            depends = { "app.pocket" },
            files = {},
        },

        ["preset.workstation"] = {
            kind = "preset",
            description = "AttaCC operator workstation",
            depends = { "app.workstation" },
            files = {},
        },

        ["preset.dashboard"] = {
            kind = "preset",
            description = "Dedicated AttaCC display/control dashboard",
            depends = { "app.dashboard" },
            files = {},
        },


    },
}
