# Architecture

## Canonical architecture

The canonical model is:

```text
+------------------------------------------------------+
| MACHINE                                              |
|                                                      |
| identity + logical network + profile                 |
|                                                      |
|  +---------------- SERVICES ----------------------+  |
|  | core / network / collector / controller        |  |
|  | display / supervisor / webbridge / client      |  |
|  | storage                                         |  |
|  +------------------------------------------------+  |
|                         |                            |
|                         v                            |
|  +---------------- MODULES -----------------------+  |
|  | steamplant / elevator / lava_buffer / ...     |  |
|  | network.storage                                |  |
|  +------------------------------------------------+  |
|                         |                            |
|                         v                            |
|  +-------------- LOGICAL I/O --------------------+  |
|  | rpm / motor_speed / main_clutch / level / ... |  |
|  +------------------------------------------------+  |
+-------------------------|----------------------------+
                          v
                 Minecraft peripherals
```

The project previously described the system as Collector -> Master -> Pocket.
Those names still exist as installation packages for compatibility, but they
are no longer the architectural model.

## Machine

A machine is one physical CC:Tweaked computer.

It has two identities:

- physical identity: `cc:<computerId>`;
- logical identity: a stable key such as `infra:steamplant-main`.

The logical identity lives in `machine.local.lua` and can be moved to
replacement hardware.

Machines also belong to a named logical network such as `infra-main`.

## Services

Services are generic runtime capabilities. They answer the question:

> What can this runtime do?

Current service names are:

```text
core
network
collector
controller
display
supervisor
webbridge
client
storage
```

Services are dependency-aware and controlled with `systemctl`.

A capability may exist on a machine while being disabled or inactive:

```text
capable = the package/runtime provides it
enabled = it should normally start
active  = it is currently allowed to run and dependencies are satisfied
```

## Modules

Modules contain application logic. They answer the question:

> What infrastructure function does this machine implement?

Examples:

```text
steamplant
elevator
lava_buffer
water_flow
network.storage
```

Modules consume services and logical I/O. They should not care about historical
package names or hard-code physical peripheral names.

## Presets and packages

A preset is an installation recipe, not a machine identity.

Current compatibility mapping:

```text
collector  -> preset.infrastructure-node
controller -> preset.automation-node
master     -> preset.supervisor
pocket     -> preset.portable-client
```

Packages are declared in `packages/manifest.lua` and resolved by `pkgctl`.
A preset package may depend on service packages and module packages.

## Configuration and state

Use the following ownership rule:

```text
machine.local.lua
    identity, name, label, logical network

profile.local.lua
    enabled modules, hardware bindings, display/runtime settings, topology

.infra/state/
    persistent application/module state

.infra/runtime/
    runtime service state, logs and transient overrides

.infra/packages.json
    installed package registry

.infra/storage/
    shared network store owned by the supervisor
```

Package updates do not own `machine.local.lua` or `profile.local.lua`.

## Networking

The node bus handles machine-level concerns:

- discovery;
- presence;
- identity conflicts;
- machine reboot;
- advertised services/modules;
- topology.

Application-specific traffic belongs to modules.

Generic module commands use a module envelope:

```lua
{
    type = "module_command",
    network = "infra-main",
    module = "elevator",
    command = "goto_floor",
    args = { floor = 2 },
    targetMachine = "infra:elevator-main",
}
```

## Shared storage

The Master/supervisor may provide:

```text
service: storage
module:  network.storage
```

It is a persistent namespaced key/value store for small shared infrastructure
data. It is intentionally not a distributed filesystem.

See [operations/network-storage.md](operations/network-storage.md).

## Design rules

1. New application logic belongs in a module.
2. Generic runtime capability belongs in a service.
3. Physical hardware mapping belongs in the machine profile.
4. Modules use logical I/O names rather than physical peripheral names.
5. Identity belongs to the machine, not to a module or package.
6. Installation presets are compatibility/deployment concepts only.
7. Cross-machine shared data should use an explicit network service such as
   `network.storage`, not hidden local files.
