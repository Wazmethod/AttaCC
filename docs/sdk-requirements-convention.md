# Standard AttaCC SDK V1.1: hardware requirements

Every AttaCC app MUST ship one static Lua contract in its package:

- Repository source: `apps/<app>/requirements.lua`
- CraftOS destination: `lib/attacc_requirements_<app>.lua`
- In `packages/manifest.lua`, declare the corresponding `files` entry.

The contract is declarative data (a Lua table), loaded by `lib.io_catalog`
without starting application code. It must be safe to evaluate before the
application starts, must contain no side effects, hardware access or secrets.

## Required shape

```lua
-- apps/pump/requirements.lua
return {
    pressure = {
        type = "pressure_sensor", -- peripheral.getType name
        direction = "input",      -- input | output | inout
        required = true,
        description = "Pressure sensor",
    },
    valve = {
        type = "redstone",        -- logical computer/relay output
        direction = "output",
        required = true,
        description = "Safety valve output",
    },
    screen = {
        type = "monitor",
        direction = "input",
        required = false,
        description = "Optional local monitor",
    },
}
```

The requirements map is keyed by stable local **role**, not a peripheral
name or CraftOS side. Roles are namespaced automatically as `<app>.<role>`
(e.g. `pump.pressure`). Required roles block hardware readiness; optional
roles appear as warnings but do not prevent startup. `description` is the
human-facing label; `type` is the CC peripheral type or `redstone`.
Only `input`, `output` and `inout` are valid direction conventions.
Applications should never embed physical peripheral names, redstone sides,
relay IDs, or local machine secrets in requirements.

## App registration

```lua
local app = require("lib.attacc").app("pump")
local requirements = require("lib.attacc_requirements_pump")
for role, spec in pairs(requirements) do
    app:io(role, {
        type = spec.type, required = spec.required,
        direction = spec.direction, label = spec.description,
    })
end
```

`app:io()` accepts the same logical roles. The package's static contract is
authoritative for **cold-start discovery**; `app:io()` describes the
running application's role. Keep both in agreement. Applications may call
`app:registerIO()` or `app:publish()` to publish runtime declarations.

## Assignment and operations

```text
ioctl init
ioctl check
ioctl list
ioctl show pump.pressure
```

All machine-specific assignments live in `/etc/io.lua`, outside the
package manager. The binding name must be the qualified role:

```lua
return {
  io = {
    bindings = {
      ["pump.pressure"] = {
        kind="peripheral", direction="input",
        peripheral="pressure_sensor_0", method="getPressure"
      },
      ["pump.valve"] = {
        kind="redstone", direction="output",
        side="back", invert=true
      }
    }
  }
}
```

Use `app:read("pressure")` for a configured no-argument read binding,
`app:write("valve",true)` for an output, and
`app:call("pressure","getPressure")` for parameterized peripheral methods.
A method call is still resolved by role; `app:call` is not an authorization
or safety boundary. Physical outputs should be configured explicitly and
checked for correctness before activation. The framework rejects ambiguous
automatic peripheral resolution rather than arbitrarily choosing one.

## Safety and network rules

Hardware requirements are declarations, not controller interlocks.
A `control.requires = {"motor"}` gate only checks hardware availability.
Applications must still enforce emergency stops, maximum speeds, ordering and
startup logic in their control layer.

Remote SDK commands use the generic `lib.sdk_commands` dispatcher with
an explicit `authorize` function. Without it, **every remote action is
rejected**. Checking `network` or `origin` alone is never authentication.
Its channel transport and trustworthy sender verification must be provided
by the host; do not expose actuator controls remotely until this is done.

## Checklist for new apps

1. Add the static requirements Lua file and package manifest mapping.
2. Register the same roles through `app:io()`.
3. Use qualified names in persistent `/etc/io.lua` bindings.
4. Use SDK I/O in application logic rather than peripheral.find/hardcoded sides.
5. Validate missing, duplicated, detached and substituted peripherals.
6. Test optional-role handling and safe output behavior.
