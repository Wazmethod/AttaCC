return {
    format = 2,
    version = "1.0.0",

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
                { src = "core/attacc.lua", dest = "lib/attacc.lua" },
                { src = "core/sdk_facade.lua", dest = "lib/sdk_facade.lua" },
                { src = "core/sdk_state.lua", dest = "lib/sdk_state.lua" },
                { src = "core/sdk_host.lua", dest = "lib/sdk_host.lua" },
                { src = "core/app_loader.lua", dest = "lib/app_loader.lua" },
                { src = "core/tools/appctl.lua", dest = "appctl.lua" },
                { src = "core/sdk_transport.lua", dest = "lib/sdk_transport.lua" },
                { src = "core/sdk_hid.lua", dest = "lib/sdk_hid.lua" },
                { src = "core/sdk_commands.lua", dest = "lib/sdk_commands.lua" },
                { src = "core/sdk_remote.lua", dest = "lib/sdk_remote.lua" },
                { src = "core/sdk_nodes.lua", dest = "lib/sdk_nodes.lua" },
                { src = "core/sdk_services.lua", dest = "lib/sdk_services.lua" },
                { src = "core/sdk_websocket.lua", dest = "lib/sdk_websocket.lua" },
                { src = "core/sdk_web_commands.lua", dest = "lib/sdk_web_commands.lua" },
                { src = "core/sdk_snapshot.lua", dest = "lib/sdk_snapshot.lua" },
                { src = "core/sdk_auth.lua", dest = "lib/sdk_auth.lua" },
                { src = "core/sha256.lua", dest = "lib/sha256.lua" },
                { src = "core/maintenance_ui.lua", dest = "lib/maintenance_ui.lua" },
                { src = "core/logctl.lua", dest = "logctl.lua" },
                { src = "core/bus.lua", dest = "lib/bus.lua" },
                { src = "core/protocol.lua", dest = "lib/protocol.lua" },
                { src = "core/machine.lua", dest = "lib/machine.lua" },
                { src = "core/profile_store.lua", dest = "lib/profile_store.lua" },
                { src = "core/config_layers.lua", dest = "lib/config_layers.lua" },
                { src = "core/config_help.lua", dest = "lib/config_help.lua" },
                { src = "core/shell_completion.lua", dest = "lib/shell_completion.lua" },
                { src = "core/nodes.lua", dest = "lib/nodes.lua" },
                { src = "core/module_router.lua", dest = "lib/module_router.lua" },
                { src = "core/io_registry.lua", dest = "lib/io_registry.lua" },
                { src = "core/io_declarations.lua", dest = "lib/io_declarations.lua" },
                { src = "core/io_catalog.lua", dest = "lib/io_catalog.lua" },
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
                { src = "modules/display_sdk.lua", dest = "lib/display_sdk.lua" },
                { src = "modules/display_sdk_graphics.lua", dest = "lib/display_sdk_graphics.lua" },
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
                { src = "modules/storage/hostctl.lua", dest = "storagehostctl.lua" },
            },
        },

        ["app.steamplant"] = {
            kind = "app",
            sdkNative = true,
            description = "SteamPlant SDK-native generator controller",
            depends = { "core.runtime", "module.network", "module.display" },
            files = {
                { src = "apps/steamplant/main.lua", dest = "apps/steamplant/main.lua" },
                { src = "apps/steamplant/config.lua", dest = "apps/steamplant/config.lua" },
                { src = "apps/steamplant/requirements.lua", dest = "apps/steamplant/requirements.lua" },
                { src = "apps/steamplant/controller.lua", dest = "apps/steamplant/controller.lua" },
                { src = "apps/steamplant/outputs.lua", dest = "apps/steamplant/outputs.lua" },
                { src = "apps/steamplant/telemetry.lua", dest = "apps/steamplant/telemetry.lua" },
            },
        },

        -- Candidate only: the legacy Master preset stays operational until
        -- SDK discovery, remote commands, events, storage and WebBridge
        -- reach functional parity.
        ["app.master-sdk-preview"] = {
            kind = "app",
            sdkNative = true,
            description = "SDK-native Master supervision candidate (read-only)",
            depends = { "core.runtime", "module.network", "module.display" },
            files = {
                { src = "apps/master/sdk_main.lua", dest = "apps/master_preview/main.lua" },
            },
        },

        ["app.webbridge-sdk-preview"] = {
            kind = "app",
            sdkNative = true,
            description = "SDK-native WebBridge relay preview (read-only)",
            depends = { "core.runtime", "module.network", "module.display" },
            files = {
                { src = "apps/master/sdk_webbridge.lua", dest = "apps/webbridge_preview/main.lua" },
            },
        },

        ["app.master"] = {
            kind = "app",
            description = "AttaCC supervision, aggregation and optional Web bridge",
            depends = { "module.network", "module.display", "module.storage-client" },
            files = {
                { src = "apps/master/main.lua", dest = "master.lua" },
                { src = "apps/master/config.lua", dest = "lib/config.lua" },
                { src = "apps/master/view.lua", dest = "lib/master_display.lua" },
                { src = "apps/master/webbridge.lua", dest = "webbridge.lua" },
                { src = "apps/master/web.example.lua", dest = "web.example.lua" },
                { src = "apps/master/tools/profilectl.lua", dest = "profilectl.lua" },
                { src = "apps/master/tools/webbridgectl.lua", dest = "webbridgectl.lua" },
                { src = "apps/master/main.lua", dest = "apps/master/main.lua" },
                { src = "apps/master/config.lua", dest = "apps/master/config.lua" },
                { src = "apps/master/view.lua", dest = "apps/master/view.lua" },
                { src = "apps/master/webbridge.lua", dest = "apps/master/webbridge.lua" },
                { src = "apps/master/web.example.lua", dest = "apps/master/web.example.lua" },
                { src = "apps/master/tools/profilectl.lua", dest = "apps/master/tools/profilectl.lua" },
                { src = "apps/master/tools/webbridgectl.lua", dest = "apps/master/tools/webbridgectl.lua" },
            },
        },

        ["app.pocket"] = {
            kind = "app",
            description = "Portable generic AttaCC control client",
            depends = { "module.network", "module.display", "module.storage-client" },
            files = {
                { src = "apps/pocket/main.lua", dest = "pocket.lua" },
                { src = "apps/pocket/config.lua", dest = "lib/config.lua" },
                { src = "apps/pocket/view.lua", dest = "lib/pocket_display.lua" },
                { src = "apps/pocket/pages.lua", dest = "lib/pocket_pages.lua" },
                { src = "apps/pocket/boot_info.lua", dest = "lib/pocket_boot_info.lua" },
                { src = "apps/pocket/view_text.lua", dest = "lib/ui.lua" },
                { src = "apps/pocket/view_graphics.lua", dest = "lib/ui_graphics.lua" },
                { src = "apps/pocket/tools/profilectl.lua", dest = "profilectl.lua" },
                { src = "apps/pocket/main.lua", dest = "apps/pocket/main.lua" },
                { src = "apps/pocket/config.lua", dest = "apps/pocket/config.lua" },
                { src = "apps/pocket/view.lua", dest = "apps/pocket/view.lua" },
                { src = "apps/pocket/pages.lua", dest = "apps/pocket/pages.lua" },
                { src = "apps/pocket/boot_info.lua", dest = "apps/pocket/boot_info.lua" },
                { src = "apps/pocket/view_text.lua", dest = "apps/pocket/view_text.lua" },
                { src = "apps/pocket/view_graphics.lua", dest = "apps/pocket/view_graphics.lua" },
                { src = "apps/pocket/tools/profilectl.lua", dest = "apps/pocket/tools/profilectl.lua" },
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
                { src = "apps/workstation/main.lua", dest = "apps/workstation/main.lua" },
                { src = "apps/workstation/config.lua", dest = "apps/workstation/config.lua" },
                { src = "apps/workstation/devices.lua", dest = "apps/workstation/devices.lua" },
                { src = "apps/workstation/tools/profilectl.lua", dest = "apps/workstation/tools/profilectl.lua" },
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
                { src = "apps/dashboard/main.lua", dest = "apps/dashboard/main.lua" },
                { src = "apps/dashboard/config.lua", dest = "apps/dashboard/config.lua" },
                { src = "apps/dashboard/view.lua", dest = "apps/dashboard/view.lua" },
                { src = "apps/dashboard/tools/profilectl.lua", dest = "apps/dashboard/tools/profilectl.lua" },
            },
        },

        ["app.example"] = {
            kind = "app",
            sdkNative = true,
            description = "Reference SDK-native application (no physical hardware)",
            depends = { "core.runtime", "module.display" },
            files = {
                { src = "apps/example/main.lua", dest = "apps/example/main.lua" },
                { src = "apps/example/requirements.lua", dest = "apps/example/requirements.lua" },
                { src = "apps/example/logic.lua", dest = "apps/example/logic.lua" },
                { src = "apps/example/views.lua", dest = "apps/example/views.lua" },
            },
        },
        ["preset.example"] = {
            kind = "preset",
            sdkApp = "example",
            description = "Reference full-SDK application",
            depends = { "app.example" },
            files = {},
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
