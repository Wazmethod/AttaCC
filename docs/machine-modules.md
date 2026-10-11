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

The next architectural step is to move service-specific code behind module
registrations and route module commands through a generic module envelope.
