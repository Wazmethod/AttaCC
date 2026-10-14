# AttaCC

AttaCC is a native application and automation framework for **CC:Tweaked**.

The SteamPlant generator is the first production application, but AttaCC is
designed so additional machines can be deployed as independent applications.

Current development version: **0.31.0-dev**.

The GitHub repository keeps the historical `steamplant-cc` name until the
native architecture is merged to the main branch.

## Source layout

```text
apps/
  master/
  pocket/
  steamplant/
  workstation/

core/
  bus.lua
  machine.lua
  nodes.lua
  protocol.lua
  runtime.lua
  ...

modules/
  display.lua
  network.lua
  storage/
```

The rule is simple:

- **apps/** contains machine/application business behavior;
- **modules/** contains reusable capabilities;
- **core/** contains the small AttaCC runtime.

A quick look inside `apps/<name>/` should explain most of what that machine
actually does.

## Runtime model

```text
application
  -> core.bus
  -> reusable modules
  -> local state/actions
  -> module.network
  -> remote AttaCC machines
```

Boot and application lifecycle use native CraftOS primitives directly.

Applications publish telemetry, actions and UI descriptors. Shared clients such
as Pocket, Master and Web can therefore expose a newly deployed controllable
machine without importing its local monitor view.

## Display model

`module.display` is shared by every app and provides monitor discovery,
geometry, resize handling and layout helpers.

Business rendering belongs to the app:

```text
apps/steamplant/view.lua
apps/master/view.lua
apps/pocket/view.lua
```

External displays are always optional. Missing display hardware never blocks the
application main loop.

## Boot

The selected preset is stored in `/etc/preset`.

Advanced Computers normally keep CraftOS plus the application in multishell,
except Pocket devices: Pocket runs its UI directly in the primary terminal so it
owns focus immediately.

The Master may additionally launch `webbridge.lua` when
`/etc/webbridge.lua` exists.

## Packages

Useful commands:

```text
pkgctl list
pkgctl status
pkgctl show <package>
pkgctl install <package>
pkgctl update
pkgctl prune
```

Primary apps:

```text
app.steamplant
app.master
app.pocket
app.workstation
```

Presets are thin package bundles which select one of these apps.

Shared storage is optional. A host that should provide it explicitly installs:

```text
pkgctl install module.storage-server
```

## Configuration

```text
/etc/preset
/etc/machine.lua
/etc/profile.lua
/etc/webbridge.lua   # Master only, optional
```

Runtime state is kept under `/run/attacc`; persistent AttaCC/package data is
kept under `/var/lib`.

## Documentation

- [Architecture](docs/architecture.md)
- [Applications](apps/README.md)
- [Machines](docs/concepts/machines.md)
- [Modules](docs/concepts/modules.md)
- [Profiles and I/O](docs/concepts/profiles-and-io.md)
- [Package manager](docs/operations/package-manager.md)
- [Network storage](docs/operations/network-storage.md)
- [Installation](docs/installation.md)
