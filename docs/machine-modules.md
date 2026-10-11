# Machine / module architecture

The project is moving from a single steam-plant application to a generic
CC:Tweaked infrastructure control network.

## Core model

A physical CC:Tweaked computer is a **machine**.

Each machine has a stable network identity:

```text
cc:<computerId>
```

The machine then advertises one or more logical **modules**.

Examples:

```text
cc:0
  - steamplant.collector

cc:1
  - steamplant.master
  - web.bridge

cc:2
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

- stable per-computer identity
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
