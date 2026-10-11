# CC Infrastructure Control

Distributed supervision and automation framework for **CC:Tweaked**.

The Create steam plant is the first production application of the framework,
not the architectural boundary of the project.

Current development version: **0.23.4-dev**.

## Canonical model

```text
Machine
  -> runtime services/capabilities
      -> application modules
          -> logical I/O
              -> Minecraft peripherals
```

A **machine** is one physical CC:Tweaked computer with a stable logical identity
and a configurable **hostname**. A **service** is a generic runtime capability
such as networking, collection, control, display, remote shell or supervision.
A **module** contains application/business logic such as `steamplant`,
`elevator`, `core.remote-shell` or `network.storage`.

A service is not an application. A module is not a system process. A machine is
not its historical package/role name.

See [docs/architecture.md](docs/architecture.md).

## Installation

Bootstrap once with `install.lua`, then run:

```text
install
reboot
```

The installer now delegates file resolution to the package manager. Installed
packages and their dependencies are tracked in `.infra/packages.json`.

Useful commands:

```text
pkgctl list
pkgctl status
pkgctl install <package>
pkgctl update
```

See [docs/operations/package-manager.md](docs/operations/package-manager.md).

## Current preset packages

```text
collector  -> preset.infrastructure-node
controller -> preset.automation-node
master     -> preset.supervisor
pocket     -> preset.portable-client
```

The old names are retained for compatibility with existing machines. New code
should reason about services and modules rather than `machine.role`.

## Shared network storage

The supervisor/Master provides the `network.storage` module through the
`storage` runtime service.

```text
storagectl ping
storagectl set demo answer 42
storagectl get demo answer
storagectl list demo
```

See [docs/operations/network-storage.md](docs/operations/network-storage.md).

## Remote administration

Every preset includes the core SSH-like remote shell service:

```text
ssh --scan
ssh <hostname>
machinectl hostname [new-hostname]
```

See [docs/operations/remote-shell.md](docs/operations/remote-shell.md).

## Shell environment

The runtime ships a small administration shell layer:

```text
profilectl edit
less <file>
console [monitor] [scale]
ssh <hostname>
systemctl ...
machinectl ...
pkgctl ...
storagectl ...
```

CraftOS MOTD is disabled by the installer/runtime shell settings. Local machine
and profile configuration live under `.infra/config/`, so they no longer
pollute root-level program completion.

## Development

- [Module development](docs/module-development.md)
- [Machine identity](docs/concepts/machines.md)
- [Runtime services](docs/concepts/services.md)
- [Application modules](docs/concepts/modules.md)
- [Profiles and logical I/O](docs/concepts/profiles-and-io.md)
- [Installation and migration](docs/installation.md)

## Web

The hosted Web UI remains an optional supervision/control plane. Modules may
publish generic UI descriptors so new controllers and monitors do not require a
hard-coded React page.

See [docs/dashboard.md](docs/dashboard.md).
