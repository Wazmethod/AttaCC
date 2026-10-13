# Module development

The project uses three separate concepts:

```text
machine = identity and deployment location
service = generic runtime capability
module  = application/business logic
```

Read [architecture.md](architecture.md) first.

## Choose module requirements

Use collection when reading physical state or publishing measurements. Use
control when implementing state machines, commands or physical outputs. A module
may use both.

Keep modules on the same machine when they belong to the same process and may
safely share a failure domain. Split them when wiring location, safety or
independent availability requires it.

## Use logical I/O

Hardware mappings belong in `profile.local.lua`.

```lua
local rpm, err = ctx.io.read("rpm")
local ok, err = ctx.io.write("motor_speed", 64)
```

Do not hard-code machine-specific peripheral names in reusable module logic.

## Collector-hosted module

Current collector modules live in:

```text
cc/collector/modules/<name>.lua
```

Typical hooks:

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

function M.update(ctx) end
function M.handleCommand(message, ctx) return false, "unsupported" end
function M.getDebug(ctx) return {} end
function M.peripheralChanged(event, name, ctx) end

return M
```

## Controller-hosted module

Controller modules live in:

```text
cc/controller/modules/<name>.lua
```

Typical automation module:

```lua
local M = { id = "elevator" }
local state = "IDLE"

function M.init(ctx)
    return true
end

function M.update(ctx)
    -- state-machine tick
end

function M.handleCommand(message, ctx)
    if message.command == "goto_floor" then
        -- validate args and change state
        return true
    end
    return false, "unknown command"
end

function M.telemetry(ctx)
    return { state = state }
end

return M
```

## Context

Hosts currently expose common runtime objects such as:

```text
ctx.config
ctx.modem
ctx.machine
ctx.protocol
ctx.services
ctx.emit
ctx.io            (collector/controller hosts)
```

Shared network data can be accessed through `lib.storage_client` when
low-frequency persistent coordination is required.

## Events

Use the common event bus:

```lua
ctx.emit(
    M.id,
    "warning",
    "LOW_LEVEL",
    "Lava buffer below 20%",
    { level = 18 }
)
```

## Package the module

Add the module to `packages/manifest.lua` as a `kind = "module"` package.
Then install it explicitly or add it as a dependency of a preset/application
package.

Do not add another file list to `install.lua`.


## Runtime rule: modules do not own processes

A module is a capability, API, driver or piece of business logic. It does not
create a multishell tab merely because it is installed.

The execution chain is:

```text
*.service
  -> daemon/binary
      -> one or more *.mod capabilities
```

For example:

```text
display.service
  -> displayd
      -> core.display.mod
      -> view descriptors published by business modules
```

Package-installed module descriptors live under:

```text
/usr/lib/modules/*.mod.lua
```

and service unit descriptors under:

```text
/usr/lib/systemd/*.service.lua
```

`lsmod` discovers module descriptors, while `systemctl` discovers service
units. `ps` shows the actual running binaries/tabs.

## Optional capability packages

Presets define defaults, not a hard ceiling. A machine can gain another
capability later by installing a package and its dependency closure.

Examples:

```text
pkgctl install module.console
pkgctl install service.display
pkgctl show service.display
```

After reboot, the generic service runner launches executable service units. A
pure module package does not launch anything by itself.
