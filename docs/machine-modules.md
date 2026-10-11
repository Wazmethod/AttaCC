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


## Named logical networks

Every machine now belongs to a named logical network.

Example:

```lua
network = "infra-main"
networkLabel = "MAIN INFRA"
```

The network name is carried by node discovery, reboot traffic and module
commands. Machines ignore node-management traffic from other named networks.

This makes it possible to keep independent groups on the same wireless
frequency/channel space, for example:

```text
infra-main
  - steam plant
  - elevator
  - factory

airship-a
  - navigation
  - propulsion
  - flight controls
```

The network identity is stored with the machine identity and is included in
`machinectl export/import`.

## Generic controller host

A new `controller` role provides the common runtime for dedicated automation
machines.

Its job is only to provide:

- machine identity
- named-network membership
- node discovery/reboot
- module command routing
- module lifecycle
- telemetry/event transport

Application logic lives in `modules/<name>.lua`.

A controller module may expose:

```lua
return {
    id = "elevator",

    init = function(ctx) end,
    update = function(ctx) end,
    handleCommand = function(message, ctx) end,
    telemetry = function(ctx) return {} end,
    peripheralChanged = function(event, name, ctx) end,
}
```

This role is intended for dedicated machines such as the elevator controller,
factory controllers or other infrastructure automation.


## Role vs runtime profile

The installed **role** is now only the reusable runtime shape:

```text
collector
controller
master
pocket
```

Per-machine behaviour belongs in `profile.local.lua`. This file is preserved
by the installer and deep-merged over the role defaults.

Use:

```text
profilectl status
profilectl init
profilectl show
profilectl reset
```

This separates:

```text
machine.local.lua  -> identity, label, logical network
profile.local.lua  -> modules, peripherals, dashboard/pages, runtime settings
```

### Collector profiles

The collector is now a generic module host. The current steam plant is the
first collector module:

```lua
collector = {
    modules = { "steamplant" },
    displayModule = "steamplant",
}
```

The runtime loads `modules/<name>.lua`. A collector module can implement:

```lua
return {
    id = "my_module",
    init = function(ctx) end,
    collect = function(ctx) return {} end,
    update = function(ctx) end,
    handleCommand = function(message, ctx) end,
    getDebug = function(ctx) return {} end,
    peripheralChanged = function(event, name, ctx) end,
}
```

The steam-plant-specific controller, I/O and telemetry remain available behind
`modules/steamplant.lua`; they are no longer hard-wired into the collector
runtime.

Steam-plant peripheral instances can be pinned per collector:

```lua
peripherals = {
    target = "create_target_0",
    speedometer = "Create_Speedometer_1",
    stressometer = "Create_Stressometer_1",
    motor = "electric_motor_0",
    accumulator = "modular_accumulator_0",
    redstoneRelay = "redstone_relay_0",
}
```

Use `nil`/omit a value to keep type-based auto-discovery.

### Pocket profiles

Each Pocket can now have its own source/dashboard/pages:

```lua
pocket = {
    sourceModule = "steamplant",
    dashboard = "steamplant",
    pages = { "status", "control", "events" },
}
```

The built-in `steamplant` dashboard maps to the existing text/CC:Graphics
renderers. Additional dashboard plugins can be added as:

```text
dashboards/<name>_text.lua
dashboards/<name>_graphics.lua
```

without changing the Pocket runtime. This allows multiple Pocket computers on
the same logical network to expose different operational views.


## Runtime services and terminal access

Advanced computers/servers now launch their long-running role runtime in a
multishell tab and leave the normal shell available. This keeps automation
running while still allowing interactive commands.

Use:

```text
systemctl list
systemctl status <service>
systemctl logs [service] [count]
systemctl config
systemctl edit
systemctl profile
```

Runtime state is stored under:

```text
.infra/runtime/services.json
.infra/runtime/runtime.log
```

Examples of services are:

```text
collector
controller
master
pocket
webbridge
display
module:steamplant
module:elevator
```

Monitor/peripheral attach and detach events are written to the local runtime log
and published on the global event bus when the host supports it.

## Declarative topology

A runtime profile can declare relationships used by the Web topology view:

```lua
topology = {
    links = {
        {
            type = "controls",
            target = "infra:elevator-main",
            module = "elevator",
        },
        {
            type = "reads",
            target = "infra:power-main",
            module = "power",
        },
    },
}
```

Supported relation names are intentionally open-ended. Recommended values are
`controls`, `reads`, `depends_on`, `feeds` and `backs_up`.

Because topology belongs to `profile.local.lua`, the same role/application
layout can later be reproduced at another site by cloning a profile and only
changing machine/network identities.

## Steam Plant rotation normalization

The Steam Plant collector exposes separate logical and physical rotation
configuration:

```lua
sensors = {
    rpm = {
        multiplier = -1,
    },
}

motor = {
    direction = 1,
}
```

`sensors.rpm.multiplier` normalizes the Speedometer sign for dashboards and
automation. The raw value is retained in telemetry as `power.rawRpm`.

`motor.direction` maps positive logical motor commands to the physical motor
orientation. Both settings can be reviewed with `systemctl config` and edited
with `systemctl edit` or the collector profile wizard.


## Web controller descriptors

Automation modules can opt into the generic Web **CONTROLLERS** page by
publishing a UI descriptor in their telemetry.

Collector modules may attach `data.ui` directly. Generic controller modules
may expose a static table or function as `module.ui`; the controller runtime
automatically attaches its result to telemetry.

Example:

```lua
M.ui = function(data, ctx)
    return {
        kind = "controller",
        title = "Main Elevator",
        subtitle = "Two-floor gantry elevator",
        state = data.state,
        status = data.error and "failed" or "active",

        metrics = {
            { label = "FLOOR", value = data.floor or "?" },
            { label = "STATE", value = data.state or "UNKNOWN" },
        },

        controls = {
            { command = "goto_floor", label = "FLOOR 1", args = { floor = 1 }, tone = "blue" },
            { command = "goto_floor", label = "FLOOR 2", args = { floor = 2 }, tone = "blue" },
            { command = "stop", label = "STOP", tone = "bad", confirm = true },
        },
    }
end
```

The Web frontend renders these descriptors generically and sends commands
through `/api/module/command`, scoped by logical network, module and target
machine. This means future controllers such as elevators do not require
hard-coded React pages just to expose state and basic controls.
