# Architecture

## Canonical architecture

The canonical runtime model is:

```text
Package / preset
      |
      v
+---------------- MACHINE ----------------+
| identity / hostname / network / profile |
|                                         |
|  Services (*.service)                   |
|    -> executable processes/binaries     |
|         -> modules (*.mod)              |
|              -> logical I/O / APIs      |
|                   -> peripherals        |
+-----------------------------------------+
```

The important distinction is:

```text
.service = an executable runtime responsibility
.mod     = reusable functionality, business logic, API or driver
binary   = the program which actually runs in a multishell tab
preset   = a default package recipe
package  = a distributable/installable unit
```

A module never receives a multishell tab merely because it is installed. Tabs
belong to running binaries such as `sshd`, `displayd`, `workstationd`,
`collectord` or `supervisord`.

## Machine

A machine is one physical CC:Tweaked computer.

It has a physical identity such as `cc:37` and a stable logical identity such
as `infra:steamplant-main`. The logical identity and hostname live under
`/etc/machine.lua`.

The historical Collector/Master/Pocket names are deployment compatibility
presets, not machine identities.

## Services

A service answers:

> Which runtime responsibility is active, and which binary performs it?

Examples:

```text
remote-shell.service -> sshd.lua
display.service      -> displayd.lua
workstation.service  -> workstationd.lua
collector.service    -> collectord.lua
controller.service   -> controllerd.lua
supervisor.service   -> supervisord.lua
```

Some foundational capabilities such as `core.service` and `network.service`
may be embedded rather than have a dedicated process.

Services are inspected and controlled with `systemctl`:

```text
systemctl list
systemctl status display.service
systemctl dependencies supervisor.service
```

## Processes

A process is the actual CraftOS program currently executing. Multishell tabs use
binary names rather than module names.

Typical workstation process list:

```text
shell | sshd | displayd | workstationd
```

Use `ps` to inspect the current multishell processes.

## Modules

A module answers:

> Which reusable feature/API/business capability is loaded?

Examples:

```text
core.display.mod
client.workstation.mod
workstation.console.mod
steamplant.mod
```

Modules do not own process lifetime. A service/process loads or consumes them.

For example:

```text
display.service
  -> displayd
       -> core.display.mod
       -> consumes UI descriptors published by business modules
```

and:

```text
collector.service
  -> collectord
       -> steamplant.mod
       -> logical I/O
```

Use `lsmod` for module health/state.

## Packages and presets

Packages are installable units declared in `packages/manifest.lua`.

A preset is only the set of packages installed by default for a machine role.
It does not prevent installing additional packages later.

For example a dashboard/controller machine may gain a display at any time:

```text
pkgctl install service.display
reboot
```

The package manager resolves dependencies automatically:

```text
service.display
  -> runtime.shell-tools
  -> module.display
      -> runtime.package-manager
```

Use:

```text
pkgctl show service.display
```

to inspect the dependency closure.

Explicitly installed packages become additional roots, so later `pkgctl update`
continues updating both the preset and manually added capabilities.

## Display model

`module.display` provides the display API/view descriptor capability.

`service.display` provides the actual display runtime:

```text
displayd.lua
displayctl.lua
```

Business modules decide **what** should be shown. The display service decides
**where/how** to render it.

A business module can publish one or several views through
`lib.display_api.lua`; `displayd` owns the monitor and view selection.

## Configuration and state

```text
/etc/machine.lua
    identity, hostname, label and network

/etc/profile.lua
    hardware bindings and per-machine feature settings

/etc/services/*.conf.lua
    per-service local overrides

/usr/lib/systemd/*.service.lua
    package-owned service definitions

/usr/lib/modules/*.mod.lua
    package-owned module descriptors

/var/lib/<component>/
    persistent component-owned state

/run/systemd/
    live service/module/process metadata

/var/lib/pkgctl/packages.json
    package roots, dependencies and owned files

/var/lib/storage/
    shared storage server data

/var/log/
    system journal and per-service logs
```

Package updates preserve machine/profile/state files.

## Design rules

1. A service owns execution and lifecycle.
2. A binary/process owns a multishell tab.
3. A module provides reusable functionality and does not create a tab by itself.
4. Business logic belongs in modules.
5. Generic runtime responsibilities belong in services.
6. Hardware bindings belong in the profile.
7. Presets select defaults only; packages may be added independently later.
8. Package dependencies, not historical roles, decide what files/capabilities are installed.
9. Modules should consume logical I/O and APIs instead of hard-coded peripheral names.


## Boot sequence

CraftOS executes `startup.lua`, which delegates immediately to `init.lua`.
The init service migrates the filesystem layout, loads service/module
definitions, resolves the enabled service graph, and launches service binaries
in dependency order. Package units are read from `/usr/lib/systemd`;
administrator overrides live under `/etc/systemd` and
`/etc/services`.


## Web capability model

Service units may declare a `web` descriptor. This does not create a Web
process on the CC computer: it only advertises that the service may be rendered
and controlled by the hosted Web control plane when a bridge is available.

The node exports a generic system graph:

```text
service -> binary/process -> modules
        -> Web capability
        -> exported data / commands
```

Lifecycle actions remain service actions. Custom Web commands are explicitly
declared by the service unit, and service code may publish structured runtime
data with `lib.webcap`.
