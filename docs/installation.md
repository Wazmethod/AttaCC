# Installation

## First install

Run the bootstrap installer on the CC computer:

```text
install
```

The installer selects or preserves a preset, installs its package closure,
preserves machine identity/profile configuration and writes `/etc/preset`.

Then:

```text
reboot
```

Available presets:

```text
collector   -> preset.infrastructure-node -> app.steamplant
master      -> preset.supervisor          -> app.master
pocket      -> preset.portable-client     -> app.pocket
controller  -> preset.automation-node     -> app.controller
workstation -> preset.workstation         -> app.workstation
```

## Updating

```text
pkgctl update
reboot
```

After a package architecture change:

```text
pkgctl update
pkgctl prune
reboot
```

`prune` removes packages outside the current dependency closure and also
cleans recognized pre-AttaCC runtime paths.

## Identity and profile

AttaCC preserves:

```text
/etc/machine.lua
/etc/profile.lua
/etc/preset
/etc/webbridge.lua
```

where applicable.

## Optional storage host

Storage is not implied by the Master role.

To host the shared store:

```text
pkgctl install module.storage-server
```

Clients use `module.storage-client`.

## Runtime layout

Current native runtime paths:

```text
/run/attacc
/var/lib/pkgctl
/var/lib/attacc
/var/lib/storage
/var/log/attacc
```

Legacy service-manager paths are removed by `pkgctl prune`.
