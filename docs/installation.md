# Installation and migration

## First bootstrap

### Existing machines using the old static installer

The old installer did not update itself. Existing deployments therefore need
one final bootstrap refresh:

```text
wget https://raw.githubusercontent.com/Wazmethod/steamplant-cc/dev/install.lua install.lua
```

After that migration, `install.lua` is owned by
`runtime.package-manager` and future package updates refresh it automatically.

### Fresh install or already migrated machine

Run:

```text
install
reboot
```

The bootstrap installs `pkgctl.lua`, then installs the selected preset package
and all of its dependencies.

Current compatibility choices:

```text
collector  -> preset.infrastructure-node
master     -> preset.supervisor
pocket     -> preset.portable-client
controller -> preset.automation-node
workstation -> preset.workstation
```

The selected preset is remembered in `/etc/preset`.

## Normal updates

After migration to the package system:

```text
install
reboot
```

or equivalently:

```text
pkgctl update
reboot
```

Use `pkgctl status` to detect missing package-owned files.

## Local configuration preservation

The package manager owns only files explicitly listed in the package manifest.
It does not own:

```text
/etc/machine.lua
/etc/profile.lua
web.local.lua
/etc/
/var/lib/<component>/
/run/systemd/
/var/lib/storage/
/var/log/
```

Normal updates therefore preserve machine identity, per-machine hardware
mapping and persistent runtime/module data.

## Identity

Production machines should use a persistent logical identity stored in
`/etc/machine.lua`.

```text
machinectl status
machinectl init
machinectl export
machinectl import <migration-code>
machinectl reset
```

When replacing a Computer, export the old logical identity, shut down the old
machine, install the replacement, import the identity and reboot.

Do not run the old and replacement Computers simultaneously with the same
logical identity.

## Profile

Per-machine hardware and runtime configuration lives in `/etc/profile.lua`.

```text
profilectl status
profilectl init
profilectl edit
profilectl reset
```

Logical I/O mappings can be inspected with:

```text
ioctl list
ioctl show <binding>
ioctl read <binding>
ioctl write <binding> <value>
```

## Shared storage verification

The supervisor preset installs the storage server package. Every current preset
installs the storage client package.

Verify connectivity with:

```text
storagectl ping
```

## Shell environment

The infrastructure shell setup disables the CraftOS MOTD and registers
completion/aliases for the administration commands.

Useful tools:

```text
profilectl edit
less <file>
less -n <file>
ssh --scan
```

The legacy `profilectl show` command remains accepted as a compatibility alias
but is no longer advertised.

## Diagnostics

```text
pkgctl status
systemctl list
machinectl status
profilectl status
storagectl ping
```


## Filesystem migration

On the first boot of the system-style runtime, `init.lua` migrates legacy
`.infra/config`, package registry, runtime, state and storage data into the
new `/etc` and `/var/lib/infra` hierarchy. Package-owned unit/module
files move to `/usr/lib` through the normal package update.
