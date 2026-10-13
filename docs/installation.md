# Installation

## First install

Run the bootstrap installer on the CC computer:

```text
install
```

The installer selects an AttaCC preset, installs its dependency closure,
preserves machine identity/profile configuration and writes `/etc/preset`.

Available presets:

```text
steamplant  -> preset.steamplant  -> app.steamplant
master      -> preset.master      -> app.master
pocket      -> preset.pocket      -> app.pocket
workstation -> preset.workstation -> app.workstation
```

Then reboot:

```text
reboot
```

## Migrating to the 0.31 native layout

0.31 removes the old preset/package names completely. On a computer installed
before 0.31, run the installer once instead of starting with `pkgctl update`:

```text
install
pkgctl prune
reboot
```

Choose the equivalent new preset when prompted. The installer preserves:

```text
/etc/machine.lua
/etc/profile.lua
/etc/webbridge.lua
```

where applicable.

After that one-time migration, normal updates use:

```text
pkgctl update
reboot
```

## Identity and profile

Machine identity is stored in:

```text
/etc/machine.lua
```

Per-machine application configuration is stored in:

```text
/etc/profile.lua
```

The active preset is stored in:

```text
/etc/preset
```

## Optional storage host

Storage is not implied by the Master preset.

To host the shared store:

```text
pkgctl install module.storage-server
```

Clients use `module.storage-client`.

## Runtime layout

```text
/run/attacc
/var/lib/pkgctl
/var/lib/attacc
/var/lib/storage
/var/log/attacc
```
