# CC Infrastructure Control

Distributed supervision and automation framework for **CC:Tweaked**.

The Create steam plant is the first production application of the framework,
not the architectural boundary of the project.

Current development version: **0.29.0-dev**.

## Native runtime model

The runtime is intentionally small and CC:Tweaked-native:

```text
preset
  -> package set
      -> application binary (main logic)
      -> modules (simple I/O / APIs)
      -> services (continuous gather/background work)
      -> network (commands / telemetry / events)
```

The rule of thumb is:

- **preset**: defines a machine usage and its default packages;
- **module**: exposes one simple capability such as redstone, display, motor,
  peripheral data or another reusable I/O API;
- **service**: performs continuous work such as gathering data, maintaining a
  connection or refreshing state;
- **application binary**: contains the machine logic and coordinates modules,
  services, actions and the network.

Business decisions belong in the application, not in generic I/O modules.

## Boot model

CraftOS remains available as the maintenance environment.

On an Advanced Computer the normal boot is:

```text
tab 1: CraftOS shell
tab 2: preset application
```

Examples:

```text
collector   -> collectord.lua
controller  -> controllerd.lua
master      -> supervisord.lua
pocket      -> clientd.lua
workstation -> workstationd.lua
```

The master may also open an optional `webbridge` tab when
`/etc/webbridge.lua` is configured.

The previous systemd-like boot graph is no longer used to start the machine.
Legacy runtime/service descriptors are temporarily retained as compatibility
metadata while applications are migrated to the native model.

See [docs/architecture.md](docs/architecture.md).

## Installation and packages

```text
install
reboot
```

Useful package commands:

```text
pkgctl list
pkgctl status
pkgctl show <package>
pkgctl install <package>
pkgctl update
```

Current presets:

```text
collector   -> preset.infrastructure-node
controller  -> preset.automation-node
master      -> preset.supervisor
pocket      -> preset.portable-client
workstation -> preset.workstation
```

Presets define defaults only. Extra modules or capabilities may still be
installed with `pkgctl`.

## Network

The logical network is the remote-control plane. It carries discovery,
heartbeats, commands, acknowledgements, telemetry and events between machines
and the hosted Web bridge.

The SSH-like remote shell is no longer part of preset installations. Remote
operations should use explicit network commands exposed by the target
application.

## Configuration

```text
/etc/preset       selected usage/preset
/etc/machine.lua  logical identity, hostname and network
/etc/profile.lua  hardware bindings and per-machine options
/etc/webbridge.lua optional hosted Web bridge configuration
```

Persistent component data remains under `/var/lib`.

## Development

- [Architecture](docs/architecture.md)
- [Module development](docs/module-development.md)
- [Machine identity](docs/concepts/machines.md)
- [Services](docs/concepts/services.md)
- [Profiles and logical I/O](docs/concepts/profiles-and-io.md)
- [Package manager](docs/operations/package-manager.md)
- [Installation and migration](docs/installation.md)
