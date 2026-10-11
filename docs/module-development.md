# Module development

The project uses three separate concepts:

```text
machine = identity
service = runtime capability
module  = application logic
```

The old package names `collector`, `controller`, `master` and `pocket`
remain as installation presets for compatibility. They are not the machine's
functional identity anymore.

## Runtime services

Current services are:

| Service | Purpose |
|---|---|
| `core` | Machine lifecycle/runtime, protected |
| `network` | Discovery, logical network and transport, protected |
| `collector` | Physical input collection and telemetry |
| `controller` | Automation/state machine and physical outputs |
| `display` | Local monitor/dashboard capability |
| `supervisor` | Master-side aggregation and supervision |
| `webbridge` | CC to hosted Web bridge |
| `client` | Portable/Pocket client |

Dependencies are declared in each preset config. Example:

```text
core
└─ network
   ├─ collector
   ├─ controller
   └─ supervisor
      └─ webbridge
```

Use:

```text
systemctl list
systemctl status <service>
systemctl start <service>
systemctl stop <service>
systemctl restart <service>
systemctl enable <service>
systemctl disable <service>
systemctl is-enabled <service>
systemctl dependencies <service>
```

`enable/disable` controls the default boot state. `start/stop` controls the
runtime service gate. Protected services such as `core` and `network`
cannot be stopped through normal service management.

## Choosing services for a module

Use the `collector` service when a module needs to read physical inputs or
publish measurements:

```text
tank/buffer level
fluid flow
RPM / stress
temperature
power/battery state
```

Use the `controller` service when a module needs state-machine logic,
commands or physical outputs:

```text
elevator
airlock
factory sequence
clutch/motor automation
interlocking
```

A module may use both. Steam Plant is the current example:

```text
steamplant
├─ collector
├─ controller
└─ display
```

Keep several modules on one physical machine when they belong to the same
physical process and may safely fail/reboot together. Split onto another
machine when wiring is remote, independent failure domains are useful, or
safety isolation is required.

## Per-machine logical I/O

Hardware mapping belongs in `profile.local.lua`, not inside the business
module.

Example:

```lua
return {
    io = {
        bindings = {
            rpm = {
                direction = "input",
                kind = "peripheral",
                peripheral = "Create_Speedometer_1",
                method = "getSpeed",
                multiplier = -1,
            },

            motor_speed = {
                direction = "output",
                kind = "peripheral",
                peripheral = "electric_motor_0",
                method = "setSpeed",
            },

            main_clutch = {
                direction = "output",
                kind = "redstone",
                relay = "redstone_relay_0",
                side = "top",
                invert = true,
            },
        },
    },
}
```

Bindings use stable logical names. Modules consume them through:

```lua
local rpm, err = ctx.io.read("rpm")
local ok, err = ctx.io.write("motor_speed", 64)
local ok, err = ctx.io.write("main_clutch", true)
```

A peripheral binding may use an exact `peripheral` name or a `type` for
auto-discovery. Numeric bindings support `multiplier` and `offset`. Boolean
redstone bindings support `invert`.

Inspect/test mappings with:

```text
ioctl list
ioctl show rpm
ioctl read rpm
ioctl write motor_speed 64
```

`ioctl write` asks for confirmation before writing.

## Collector-hosted modules

Collector package modules currently live in:

```text
cc/collector/modules/<name>.lua
```

Enable them in the machine profile:

```lua
return {
    collector = {
        modules = { "steamplant", "lava_buffer" },
        displayModule = "steamplant",
    },
}
```

Supported hooks:

```lua
local M = {
    id = "lava_buffer",
}

function M.init(ctx)
    return true
end

function M.collect(ctx)
    local level = ctx.io.read("lava_level")

    return {
        level = level,
        ui = {
            kind = "monitor",
            title = "Lava Buffer",
            state = "ONLINE",
            status = "active",
            metrics = {
                { label = "LEVEL", value = tostring(level), unit = "%" },
            },
        },
    }
end

function M.update(ctx)
end

function M.handleCommand(message, ctx)
    return true
end

function M.getDebug(ctx)
    return {}
end

function M.peripheralChanged(event, name, ctx)
end

return M
```

The host runtime adds network, machine, module, timestamp and transport type to
telemetry automatically.

## Controller-hosted modules

Controller package modules currently live in:

```text
cc/controller/modules/<name>.lua
```

Enable them with:

```lua
return {
    controller = {
        tick = 0.10,
        modules = { "elevator" },
    },
}
```

Example:

```lua
local M = {
    id = "elevator",
}

local state = "IDLE"

function M.init(ctx)
    ctx.io.write("move_up", false)
    ctx.io.write("move_down", false)
    return true
end

function M.update(ctx)
    -- state-machine tick
end

function M.handleCommand(message, ctx)
    if message.command == "goto_floor" then
        local floor = message.args and message.args.floor
        -- validate + update state
        return true
    end
    return false, "unknown command"
end

function M.telemetry(ctx)
    return {
        state = state,
        floor = 1,
    }
end

M.ui = function(data, ctx)
    return {
        kind = "controller",
        title = "Main Elevator",
        state = data.state,
        status = "active",
        metrics = {
            { label = "FLOOR", value = tostring(data.floor or "?") },
        },
        controls = {
            { command = "goto_floor", label = "FLOOR 1", args = { floor = 1 }, tone = "blue" },
            { command = "goto_floor", label = "FLOOR 2", args = { floor = 2 }, tone = "blue" },
            { command = "stop", label = "STOP", tone = "bad", confirm = true },
        },
    }
end

return M
```

## Module context

Current hosts expose:

```text
ctx.config
ctx.modem
ctx.machine
ctx.protocol
ctx.services
ctx.emit
```

Collector/controller hosts also expose:

```text
ctx.io
```

Collector additionally exposes:

```text
ctx.nodeBus
```

Publish events through the common event bus:

```lua
ctx.emit(
    M.id,
    "warning",
    "LOW_LEVEL",
    "Lava buffer below 20%",
    { level = 18 }
)
```

## Installation presets

Current package/preset mapping:

```text
collector package  -> infrastructure-node
  core + network + collector + controller + display

controller package -> automation-node
  core + network + controller

master package     -> supervisor
  core + network + supervisor + display + webbridge

pocket package     -> portable-client
  core + network + client + display
```

The legacy package names are kept so existing machines can update without a
destructive migration. New code should reason about services, not
`machine.role`.

## Making a module installable

Shipped files are still listed explicitly in `install.lua`.

For a new controller module:

```lua
controller = {
    ...
    "modules/elevator.lua",
}
```

For a new collector module:

```lua
collector = {
    ...
    "modules/lava_buffer.lua",
}
```

Local experimental modules may be copied manually into the matching
`modules/` directory.

## Reference values

- Runtime services: `core`, `network`, `collector`, `controller`, `display`, `supervisor`, `webbridge`, `client`.
- Presets: `infrastructure-node`, `automation-node`, `supervisor`, `portable-client`.
- Display backends: `auto`, `text`, `ccgraphics`.
- Collector text pages: `control`, `gen`, `data`, `logs`, `debug`.
- Collector graphics tabs: `dashboard`, `graphs`, `events`, `machines`, `debug`.
- Master pages: `dashboard`, `graphs`, `events`, `machines`, `topology`, `debug`.
- Pocket built-in dashboard: `steamplant`.
- Pocket pages: `status`, `control`, `motor`, `events`, `system`.
- Pocket transport: `master`, `direct`.
- Web UI kinds: `controller`, `monitor`.
- Web statuses: `active`, `warning`, `failed`.
- Control tones: `blue`, `good`, `warn`, `bad`.
- Recommended topology relations: `controls`, `reads`, `depends_on`, `feeds`, `backs_up`.
- Steam Plant touch profiles: `normal`, `angled3`, `mirror_x`.
- Steam Plant redstone modes: `auto`, `relay`, `direct`.
