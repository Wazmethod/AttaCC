# Profiles and logical I/O

## Configuration ownership

`machine.local.lua` owns identity:

```text
logical key
name / label
logical network
```

`profile.local.lua` owns machine-specific behaviour:

```text
modules
peripheral bindings
display configuration
runtime settings
topology
```

Neither file is owned by the package manager.

## Logical I/O

Modules should use stable logical names:

```lua
local rpm = ctx.io.read("rpm")
ctx.io.write("motor_speed", 64)
ctx.io.write("main_clutch", true)
```

The profile resolves those names to physical devices:

```lua
io = {
    bindings = {
        rpm = {
            direction = "input",
            kind = "peripheral",
            peripheral = "Create_Speedometer_1",
            method = "getSpeed",
            multiplier = -1,
        },
        main_clutch = {
            direction = "output",
            kind = "redstone",
            relay = "redstone_relay_0",
            side = "top",
            invert = true,
        },
    },
}
```

Inspect and test bindings with:

```text
ioctl list
ioctl show <binding>
ioctl read <binding>
ioctl write <binding> <value>
```
