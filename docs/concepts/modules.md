# Application modules

A **module** is reusable functionality: business logic, an API, a driver, a
renderer provider, a protocol capability, or another feature consumed by a
running service.

Modules are displayed as `*.mod` units by:

```text
lsmod
```

Examples:

```text
steamplant.mod
core.display.mod
client.workstation.mod
workstation.console.mod
```

A module is **not** a process. Installing/loading a module does not imply a
multishell tab. The service binary which consumes the module owns execution.

Preferred model:

```text
service
  -> binary/process
      -> module(s)
          -> runtime APIs / logical I/O
              -> physical peripherals
```

For example:

```text
display.service
  -> displayd
      -> core.display.mod
      -> UI descriptors from steamplant.mod / elevator.mod / ...
```

and:

```text
collector.service
  -> collectord
      -> steamplant.mod
          -> rpm / motor_speed / clutch logical I/O
```

Modules may publish telemetry, events, commands, shared state and display/Web UI
descriptors. They should not hard-code historical preset names or physical
peripheral names when a profile binding/API can be used.

Package modules can be installed as dependencies of services/presets or as
explicit package roots. Dependency resolution is handled by `pkgctl`.
