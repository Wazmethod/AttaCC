# Module development

This guide explains how to choose a runtime role, where modules live, and how to create a new collector/controller module.

## Role vs module

`role = runtime lifecycle` and `module = application logic`.

Use `collector` for physical telemetry/readout-oriented nodes, `controller` for dedicated automation/state machines, `master` for supervision/Web bridge, and `pocket` for portable clients.

Keep several modules on one machine when they belong to the same physical process, share local peripherals, and may safely fail/reboot together. Split them when wiring is remote, isolation is useful, or independent failure domains are required.

## Collector modules

Location: `cc/collector/modules/<name>.lua`.

Enable in `profile.local.lua`:

```lua
return {
  collector = {
    modules = { "steamplant", "lava_buffer" },
    displayModule = "steamplant",
  },
}
```

Supported hooks: `init(ctx)`, `collect(ctx)`, `update(ctx)`, `handleCommand(message, ctx)`, `getDebug(ctx)`, `peripheralChanged(event, name, ctx)`.

`collect()` returns application telemetry. The collector runtime adds generic transport fields such as network, machine, module, timestamp and type.

Example read-only Web card:

```lua
function M.collect(ctx)
  local level = 72
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
```

## Controller modules

Location: `cc/controller/modules/<name>.lua`.

Enable in `profile.local.lua`:

```lua
return {
  controller = {
    tick = 0.10,
    modules = { "elevator" },
  },
}
```

Supported hooks: `init(ctx)`, `update(ctx)`, `handleCommand(message, ctx)`, `telemetry(ctx)`, `peripheralChanged(event, name, ctx)`.

A controller may expose `M.ui` as a table or function. The runtime attaches it to telemetry for the Web OPERATIONS page.

```lua
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
```

## Context

Both runtimes expose at least `ctx.config`, `ctx.modem`, `ctx.machine`, `ctx.protocol`, `ctx.emit`. Collector also exposes `ctx.nodeBus`.

Use `ctx.emit(module, level, code, message, extra)` for events so they flow through the normal event bus and Web logs.

## Making a module installable

The installer currently lists shipped files explicitly. Add a new module path to the matching role in `install.lua`, for example `modules/elevator.lua` or `modules/lava_buffer.lua`. Local experimental modules can be copied manually.

## Complete controller flow

1. Create `cc/controller/modules/elevator.lua`.
2. Add `modules/elevator.lua` to the controller list in `install.lua`.
3. Install role `controller`.
4. Run `machinectl init` and assign a logical key/network.
5. Run `profilectl init` and enable `elevator`.
6. Reboot.
7. Verify with `systemctl list`.
8. Check Web DISCOVERY / OPERATIONS / LOGS.

## Complete collector flow

1. Create `cc/collector/modules/lava_buffer.lua`.
2. Add `modules/lava_buffer.lua` to the collector list in `install.lua`.
3. Install role `collector`.
4. Run `machinectl init`.
5. Run `profilectl init` and enable `lava_buffer`.
6. Use `displayModule = nil` for a headless collector.
7. Pin peripheral names when auto-discovery is ambiguous.
8. Reboot and verify with `systemctl list`.

## Reference values

- Roles: `collector`, `controller`, `master`, `pocket`.
- Display backends: `auto`, `text`, `ccgraphics`.
- Collector text pages: `control`, `gen`, `data`, `logs`, `debug`.
- Collector graphics tabs: `dashboard`, `graphs`, `events`, `machines`, `debug`.
- Master pages: `dashboard`, `graphs`, `events`, `machines`, `topology`, `debug`.
- Pocket built-in dashboard: `steamplant`; custom dashboards use `dashboards/<name>_text.lua` and `dashboards/<name>_graphics.lua`.
- Pocket pages: `status`, `control`, `motor`, `events`, `system`.
- Pocket transport: `master`, `direct`.
- Web UI kinds: `controller`, `monitor`.
- Web status values: `active`, `warning`, `failed`.
- Control tones: `blue`, `good`, `warn`, `bad`.
- Recommended topology relations: `controls`, `reads`, `depends_on`, `feeds`, `backs_up`.
- Steam Plant touch profiles: `normal`, `angled3`, `mirror_x`.
- Steam Plant redstone modes: `auto`, `relay`, `direct`.
