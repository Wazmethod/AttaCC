# In-game installation

## Required machines

The current default mapping is:

- CC computer ID `0`: Collector
- CC computer ID `1`: Master / Advanced Server
- CC computer ID `2`: Advanced Pocket Computer

The installer also allows selecting a different role manually.

## Collector wiring

The Collector needs access to these peripheral types:

- `create_target`
- `Create_Speedometer`
- `Create_Stressometer`
- `electric_motor`
- `modular_accumulator`
- a wireless modem

The Create Target must receive a Display Link configured for Boiler Status.

Redstone outputs:

- top -> MAIN clutch
- left -> ALT clutch
- right -> GEN clutch

For a rack-mounted Advanced Server, use a CC:Tweaked **Redstone Relay** on the
wired peripheral network. The relay exposes the same `setOutput/getOutput`
methods as the computer redstone API.

The collector defaults to:

```lua
M.redstone = {
    mode = "auto",
    relayName = nil,
    mainClutch = "top",
    alternatorClutch = "left",
    genClutch = "right",
}
```

With `mode = "auto"`, a discovered `redstone_relay` is preferred and direct
computer redstone is used only when no relay is present.

If several relays are connected, set the exact peripheral name in
`relayName` (for example `"redstone_relay_0"`) and use
`mode = "relay"`.

## Master

The Master needs:

- wireless modem
- wall monitor
- optional speaker

## Pocket

The Pocket needs a wireless modem.

## HTTP installation

`install.lua` downloads the appropriate files from GitHub. Since the repository is private, use a fine-grained GitHub token limited to this repository with **Contents: Read-only**.

If the repository is later made public, the token can be left blank.

HTTP must be enabled/allowed by CC:Tweaked.


## Persistent machine identity

The CC:Tweaked computer ID is treated as a physical identifier only. Production
machines should use a logical identity stored in `machine.local.lua`.

On a fresh install, the installer offers:

1. create a new persistent logical identity;
2. import an identity from a replaced machine;
3. temporarily use `cc:<computerId>`.

For a new machine, prefer a semantic key such as:

```text
infra:steamplant-main
infra:factory-a
infra:storage-main
```

Normal updates preserve `machine.local.lua`.

Check the active identity with:

```text
machinectl status
```

### Replacing a computer

On the old machine:

```text
machinectl export
```

The migration code is written to `machine-migration.txt`. Open it with:

```text
edit machine-migration.txt
```

to copy the complete `IM1-...` value, then shut the old computer down.

A custom filename can also be used:

```text
machinectl export my-machine.txt
```

On the replacement Advanced Computer, run the installer, select the same role,
then choose the identity import option and paste the migration code. You can
also import it afterwards:

```text
machinectl import IM1-...
reboot
```

The physical CC ID may change. The logical machine key, name, label, modules and
tags are retained.

Running two computers with the same logical key at the same time is considered
an identity conflict and is reported by the node discovery layer.


## Collector local display module

Collectors advertise the optional `collector.display` module. When enabled,
the collector looks for an attached or wired-network `monitor` peripheral and
renders a local control/status dashboard.

Default configuration:

```lua
M.localDisplay = {
    enabled = true,
    monitorName = nil,
}

M.display = {
    preferred = "auto",
    graphicsMode = 1,
    textScale = 0.5,
}
```

With `monitorName = nil`, the first monitor found is used. If several monitors
are on the wired network, set the exact peripheral name, for example:

```lua
M.localDisplay.monitorName = "monitor_3"
```

When CC:Graphics is exposed by the monitor, the collector prefers the graphics
dashboard and automatically falls back to the text UI otherwise.

The local display includes telemetry and touch controls for startup, abort,
auto-restart arming, clutches, motor stop and running topology. The graphics
backend also exposes graphs, events, machine discovery and debug pages.

The monitor may be connected through CC:Tweaked wired modems/network cable; it
does not need to be physically adjacent to the collector.
