# Machine / module architecture

The project is moving from a single steam-plant application to a generic
CC:Tweaked infrastructure control network.

## Core model

A physical CC:Tweaked computer is a **machine**.

Each machine has two identities:

- a **physical identity** generated from CC:Tweaked: `cc:<computerId>`;
- a **logical machine key** stored in `machine.local.lua`, for example
  `infra:steamplant-main`.

The logical key is the stable identity used by the infrastructure network. It
can be moved to another physical Advanced Computer without changing the
machine's logical identity.

The machine then advertises one or more logical **modules**.

Examples:

```text
infra:steamplant-main   (physical cc:37)
  - steamplant.collector

infra:control-master    (physical cc:41)
  - steamplant.master
  - web.bridge

infra:portable-1        (physical cc:52)
  - steamplant.remote
```

Future machines can advertise unrelated infrastructure without changing the
node-management layer:

```text
cc:10
  - storage.monitor
  - power.grid

cc:11
  - factory.line
  - logistics.router

cc:12
  - airship.navigation
```

The node bus is responsible only for machine-level functions such as discovery,
presence, identity and reboot. Application-specific commands remain inside
their module.

## Machine configuration

Each role has a default `config.machine` table. It can be overridden without
editing installed files by creating `machine.local.lua`:

```lua
return {
    name = "boiler-room-a",
    label = "BOILER ROOM A",
    modules = {
        "steamplant.collector",
        "power.grid",
    },
    tags = {
        "infra",
        "boiler-room",
    },
}
```

The installer does not manage `machine.local.lua`, so local identity survives
updates.

## Current migration state

The steam-plant controller is currently the first infrastructure module. Its
existing telemetry/control protocol is intentionally kept compatible while the
generic machine layer is introduced.

The generic machine layer already provides:

- persistent logical identity independent from CC computer ID
- physical identity tracking
- module advertisement
- tags and labels
- node discovery
- online presence
- single/multi-machine reboot
- Master/Pocket/Web visibility

Service-specific commands are now routed through a generic module envelope.

Example:

```lua
{
    type = "module_command",
    module = "steamplant",
    command = "procedure",
    args = {},
    targetMachine = "cc:0",
    origin = "cc:2",
    id = "...",
}
```

The collector owns a module router and registers the steam plant as its first
module. Legacy `target = "steam_plant"` messages are still normalized at the
protocol edge during migration.

Steam-plant telemetry now advertises:

```text
type    = module_telemetry
module  = steamplant
machine = cc:<id>
```

while retaining the legacy `source = "steam_plant"` field for existing
interfaces.

The web backend exposes a generic authenticated endpoint:

```text
POST /api/module/command
```

with `module`, `command`, optional `args`, and optional
`targetMachine`. The old `/api/command` endpoint remains as a compatibility
wrapper for the steamplant module.

## UI model

The Pocket and wall display are clients of the machine/module network, not
steam-plant-specific transports. The current UI still has a dedicated
steamplant dashboard, but machine discovery and module inventory are generic.

CC:Graphics Pocket rendering uses a hybrid terminal strategy: the opened Pocket
GUI stays in graphics mode while the underlying text terminal is kept updated
with a compact status HUD. CC:Tweaked's in-hand Pocket renderer reads that text
terminal, so the held item can remain useful even though CC:Graphics does not
render its graphics framebuffer on the in-hand model.


## Installation, replacement and migration

Fresh installs run an identity wizard after the role files are downloaded.

A production machine should have a persistent logical key such as:

```text
infra:steamplant-main
infra:factory-a
infra:datacenter-power
```

The local identity file is never overwritten by normal updates, so:

```text
install
reboot
```

preserves the machine identity on reinstall/update.

To replace hardware, export the identity on the old machine:

```text
machinectl export
```

Copy the generated `IM1-...` migration code, shut down the old machine, then
install the correct role on the replacement and choose **Import identity** in
the installer. It may also be imported afterwards:

```text
machinectl import IM1-...
reboot
```

The new Advanced Computer gets a new physical `cc:<id>`, but retains the old
logical machine key.

Do not run the old and replacement computers simultaneously with the same
logical key. The node layer detects this condition and reports an
`IDENTITY CONFLICT` on the Master, Pocket and Web machine views.

Useful commands:

```text
machinectl status
machinectl init
machinectl export
machinectl import <code>
machinectl reset
```


## Local runtime storage

Project/runtime metadata now lives under the generic `.infra/` namespace
instead of project-specific `.steamplant-*` files.

Current layout:

```text
.infra/
  version.json
  state/
    steamplant-controller.json
    steamplant-outputs.json
```

Existing installations are migrated automatically from:

```text
.steamplant-version.json
.steamplant-controller.json
.steamplant-outputs.json
```

The generic namespace is intended to host state for future modules such as
elevators, factory automation and power control without adding new
project-specific dotfiles at the filesystem root.
