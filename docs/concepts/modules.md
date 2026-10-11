# Application modules

A **module** is an autonomous infrastructure/application function.

Examples:

```text
steamplant
elevator
lava_buffer
water_flow
factory_line
network.storage
```

A module consumes runtime services and logical I/O. It should not depend on the
historical names `collector`, `controller`, `master` or `pocket` as
machine identities.

Preferred dependency direction:

```text
module
  -> ctx.io / runtime APIs
      -> profile logical bindings
          -> physical peripheral
```

Avoid:

```lua
peripheral.wrap("Create_Speedometer_1")
```

inside reusable business logic when a logical binding can be used instead.

Modules may publish telemetry, events, commands and generic Web UI descriptors.
A module can use multiple services when appropriate. For example:

```text
steamplant
  requires collection + control + optional display

lava_buffer
  requires collection

elevator
  requires control and usually collection
```

The package manager allows modules to be distributed independently from preset
runtime bundles.
