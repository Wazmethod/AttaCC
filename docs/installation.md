# Installation and migration

## First bootstrap

Download or paste the current `install.lua`, then run:

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
```

The selected preset is remembered in `.infra/install-preset`.

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
machine.local.lua
profile.local.lua
web.local.lua
.infra/state/
.infra/runtime/
.infra/storage/
```

Normal updates therefore preserve machine identity, per-machine hardware
mapping and persistent runtime/module data.

## Identity

Production machines should use a persistent logical identity stored in
`machine.local.lua`.

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

Per-machine hardware and runtime configuration lives in `profile.local.lua`.

```text
profilectl status
profilectl init
profilectl show
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

## Diagnostics

```text
pkgctl status
systemctl list
machinectl status
profilectl status
storagectl ping
```
