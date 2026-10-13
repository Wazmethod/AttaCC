# Services

In the native runtime, a **service** means continuous background work required
by an application.

Examples:

```text
network heartbeat
telemetry gathering
display refresh
WebSocket bridge
periodic sensor sampling
```

A service is not a Linux/systemd-style process-management abstraction.

## Responsibility split

```text
module      simple reusable I/O/API
service     repeated/background work
application machine-specific logic
```

For example:

```text
motor module
  -> read/set motor state

telemetry service
  -> sample motor state periodically

collector application
  -> decide whether the motor must start/stop
```

## Execution

The main preset application is launched directly by `startup.lua` in a
multishell tab.

A service may run inside that application with an event loop, timer or
`parallel`, or use a dedicated binary when separation is genuinely useful.

Do not create a dedicated process merely to mimic an init system.

## 0.29 compatibility layer

Existing applications still call `lib.services` and use package-owned
`*.service.lua` descriptors. These files are temporarily retained so the
runtime can be migrated without changing all production logic at once.

They are compatibility metadata only: `startup.lua` no longer resolves or
launches a service graph.

New code should not depend on `systemctl` lifecycle semantics.

## Web bridge

The Web bridge is a legitimate separate background task because it owns a
persistent external WebSocket connection. On the master it is launched only
when `/etc/webbridge.lua` exists.
