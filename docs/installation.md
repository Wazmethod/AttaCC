# Installation and migration

## First bootstrap

For an existing machine, refresh the installer once:

```text
wget https://raw.githubusercontent.com/Wazmethod/steamplant-cc/dev/install.lua install.lua
```

Then run:

```text
install
reboot
```

The installer bootstraps `pkgctl.lua`, installs the selected preset and its
package dependencies, preserves local configuration, then stores the preset in:

```text
/etc/preset
```

Current choices:

```text
collector   -> preset.infrastructure-node
master      -> preset.supervisor
pocket      -> preset.portable-client
controller  -> preset.automation-node
workstation -> preset.workstation
```

## Native boot

Since 0.29, boot no longer starts the old systemd-like service graph.

On an Advanced Computer:

```text
tab 1: CraftOS shell
tab 2: preset application
```

The master may also start `webbridge.lua` if `/etc/webbridge.lua` exists.

This is intentional: the CraftOS shell remains immediately available for
maintenance while the main application continues independently.

## Normal updates

```text
pkgctl update
reboot
```

or:

```text
install
reboot
```

Use:

```text
pkgctl status
```

to verify package-owned files.

## Local configuration

Updates preserve:

```text
/etc/machine.lua
/etc/profile.lua
/etc/webbridge.lua
/var/lib/<component>/
```

## Identity

```text
machinectl status
machinectl init
machinectl export
machinectl import <migration-code>
machinectl reset
```

Do not run two computers simultaneously with the same logical identity.

## Profile and I/O

```text
profilectl status
profilectl init
profilectl edit
profilectl reset

ioctl list
ioctl show <binding>
ioctl read <binding>
ioctl write <binding> <value>
```

## Remote control

SSH is no longer installed by the standard presets.

Machine-to-machine and Web control should use the logical network command
protocol. The old `service.remote-shell` package is retained only as an
optional compatibility package during the transition.

## Diagnostics

Start with:

```text
pkgctl status
machinectl status
profilectl status
```

Then use the CraftOS shell directly to inspect files, peripherals and running
multishell tabs.

## Migration note

0.29 keeps compatibility files from the previous runtime so existing
applications can be migrated incrementally. The canonical boot path no longer
depends on `init.lua`, `systemctl`, `servicerun.lua` or `sshd.lua`.

Once the native applications no longer use the compatibility service/runtime
APIs, those files can be removed in a later cleanup release.
