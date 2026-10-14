# Machines

A **machine** is one physical CC:Tweaked computer participating in an
infrastructure network.

## Physical and logical identity

```text
physical identity = cc:<computerId>
logical identity  = infra:<stable-name>
```

The physical identity changes when the Computer block is replaced. The logical
identity is stored in `/etc/machine.lua` and is intended to survive hardware
replacement.

Example:

```lua
return {
    key = "infra:steamplant-main",
    hostname = "steam-main",
    label = "STEAM PLANT MAIN",
    network = "infra-main",
    networkLabel = "MAIN INFRA",
}
```

Use `machinectl export` and `machinectl import <code>` when replacing
hardware. Do not run two machines with the same logical identity at the same
time; the node layer reports an identity conflict.

A machine advertises its apps, modules, capabilities, topology and runtime state through
the node bus.
