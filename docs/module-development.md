# Module development

The native architecture uses four simple concepts:

```text
preset      deployment usage / package set
module      reusable I/O or API capability
service     continuous/background work
application machine-specific logic
```

Read [architecture.md](architecture.md) first.

## Keep modules small

A module should expose a device or capability and avoid plant policy.

Good module responsibilities:

```text
redstone input/output
motor read/control
boiler data
battery data
display primitives
network send/receive helpers
peripheral discovery
```

Example:

```lua
local M = {}

function M.read()
    return {
        speed = motor.getSpeed(),
        consumption = motor.getEnergyConsumption(),
    }
end

function M.setSpeed(rpm)
    return pcall(motor.setSpeed, rpm)
end

function M.stop()
    return pcall(motor.stop)
end

return M
```

Do not put rules such as "stop the plant when stress is above X" in the motor
module. That belongs in the application logic.

## Logical I/O

Machine-specific hardware mapping belongs in `/etc/profile.lua`.

Existing hosts expose logical I/O through:

```lua
local value, err = ctx.io.read("rpm")
local ok, err = ctx.io.write("motor_speed", 64)
```

## Services

Use a service when work must happen repeatedly:

```lua
local function telemetryLoop()
    while true do
        local data = motor.read()
        -- publish/update state
        sleep(0.5)
    end
end
```

A service may be a coroutine/event handler inside the main application. A
separate multishell process should only be used when isolation is useful.

## Application logic

The application owns decisions and actions:

```text
input/module data
      |
      v
application logic
      |
      +-> local action
      +-> network event
      +-> display state
```

Network commands should call application actions rather than raw I/O.

## Existing module hosts

During the 0.29 transition, Collector and Controller retain their current module
hooks such as `init`, `collect`, `update`, `telemetry`,
`handleCommand` and `peripheralChanged`.

This allows the SteamPlant logic to keep working while modules are split into
smaller device-oriented capabilities.

## Packaging

Add reusable capabilities to `packages/manifest.lua` as module packages.
Add background capabilities as service packages only when they actually need
continuous work.

Do not add file lists to `install.lua`; `pkgctl` owns package deployment.

## Legacy descriptors

`/usr/lib/modules/*.mod.lua` and `/usr/lib/systemd/*.service.lua` may still
exist during migration. New code should not assume that a service descriptor
creates a process or a multishell tab.

The native boot path launches the preset application directly.
