# Architecture

## Canonical native model

```text
                     PRESET
                       |
                 installs packages
                       |
        +--------------+--------------+
        |              |              |
        v              v              v
     MODULES         SERVICES      APPLICATION
   simple I/O      background        main logic
   and APIs          gather             |
        |              |                |
        +--------------+--------+-------+
                                |
                             NETWORK
                                |
                    commands / data / events
```

The architecture is deliberately closer to an embedded controller than to a
Unix workstation.

## Presets

A preset defines a machine **usage** and the default package set for that usage.

Current compatibility names are:

```text
collector
controller
master
pocket
workstation
```

A preset is not the machine identity. Identity remains in
`/etc/machine.lua`.

## Modules

A module should be small and reusable. It answers questions such as:

- how do I read this peripheral?
- how do I set this redstone output?
- how do I control this motor?
- how do I draw to this display backend?
- how do I send a packet?

A module should not decide plant policy.

Example:

```lua
motor.getSpeed()
motor.setSpeed(64)
motor.stop()
```

Safety rules and automation decisions belong to the application logic.

## Services

A service is continuous background work required by an application.

Examples:

- gather telemetry periodically;
- maintain network state/heartbeats;
- refresh a display;
- maintain an external connection.

Services are intentionally lightweight. They are not a systemd-like lifecycle
framework.

During the 0.29 transition, legacy `*.service.lua` descriptors and
`lib.services` remain available as compatibility metadata for existing
applications. They no longer drive the boot sequence.

## Application binaries

The application binary is the machine brain:

```text
collectord.lua
controllerd.lua
supervisord.lua
clientd.lua
workstationd.lua
```

It combines module data, service state, network input and local input, then
applies the machine-specific logic.

A useful separation is:

```text
module  = how to interact with something
service = continuously observe/maintain something
action  = perform one operation
main    = decide when and why
```

## Boot sequence

CraftOS executes `startup.lua`.

On Advanced Computers, `startup.lua` leaves the CraftOS shell available and
opens the selected preset application in another multishell tab:

```text
CraftOS shell | application
```

The master may additionally launch `webbridge.lua` when
`/etc/webbridge.lua` exists.

There is no automatic service-graph resolution and no SSH daemon in the native
boot path.

On a Computer without multishell support the application runs in the current
terminal as a compatibility fallback.

## Native Master

The Master is an AttaCC application, not an init/service manager.

```text
supervisord.lua
  -> logical network / node discovery
  -> shared storage server
  -> SteamPlant supervision/command aggregation
  -> Pocket status broadcast
  -> display module when a monitor is present

webbridge.lua
  -> optional separate program
  -> launched only when /etc/webbridge.lua exists
```

Network, storage and Pocket broadcast are active because the Master application
is running; they are not gated by `systemctl`-style service state.

Display is opportunistic. A missing monitor does not stop the Master. The
display module becomes inactive and is re-initialized automatically when a
monitor is attached.

The 0.29 Master keeps the existing packet channels and message formats so that
older Pocket and SteamPlant nodes can remain online during the migration.

## Network model

The logical network replaces remote shell administration for normal operation.

Packets are grouped around a small set of purposes:

```text
discovery
heartbeat
command
response / ack
telemetry
event
```

Commands target application actions rather than raw I/O. For example:

```text
Master/Web
   -> command: generator.start
      -> target application
         -> action
            -> redstone/motor module
```

This keeps physical policy on the machine which owns the hardware.

## Display model

Display is a module/capability consumed by an application or a lightweight
display service.

The application chooses **what** to show. The display module/backend chooses
**how** to render it.

Text terminals, monitors and CC: Graphics can therefore expose different
renderers without changing the underlying machine logic.

## Files and configuration

The project still keeps stable configuration and package state separated from
code:

```text
/etc/preset
/etc/machine.lua
/etc/profile.lua
/etc/webbridge.lua

/var/lib/pkgctl/
/var/lib/<component>/
```

Legacy `/usr/lib/systemd`, `/run/systemd` and service descriptor data may
still exist on machines upgraded from 0.28 while the compatibility layer is
being removed. They are not the canonical 0.29 boot model.

## Design rules

1. Presets define usage and a package set.
2. Modules stay small and expose capabilities/I/O.
3. Services only perform continuous background work.
4. Applications own machine-specific logic and safety decisions.
5. Network commands invoke application actions, not raw hardware directly.
6. Hardware mappings belong in the profile.
7. CraftOS remains the maintenance/debug shell.
8. Do not recreate Unix process, init or SSH abstractions unless a concrete
   CC:Tweaked requirement justifies them.
