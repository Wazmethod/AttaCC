# Package manager

The package manager installs presets, services, modules and runtime tools from
`packages/manifest.lua`.

The local registry is:

```text
/var/lib/pkgctl/packages.json
```

## Package kinds

```text
runtime  shared runtime/tooling
service  executable runtime responsibility
module   reusable API/business/driver functionality
preset   default deployment recipe
```

Package kind and runtime role are related but not identical: the package
describes distribution/ownership, while `systemctl`, `ps` and `lsmod`
describe the running machine.

## Dependencies

Dependencies are recursively resolved before installation.

Example:

```text
service.display
  -> runtime.shell-tools
  -> module.display
      -> runtime.package-manager
```

Installing the service therefore installs everything required by it:

```text
pkgctl install service.display
reboot
```

A preset is only an initial/default root. Additional packages may be installed
on any compatible machine later.

For example an automation/dashboard machine can gain a monitor runtime without
changing preset:

```text
pkgctl install service.display
displayctl use auto
reboot
```

Explicitly installed packages are stored as roots. `pkgctl update` resolves
all explicit roots again, so manually added capabilities continue to be
maintained alongside the preset.

## Commands

```text
pkgctl list
pkgctl status
pkgctl show <package>
pkgctl deps <package>
pkgctl install <package>
pkgctl update
pkgctl update <package>
pkgctl configure <package>
```

`show`/`deps` displays the direct dependencies and resolved dependency
closure.

## File ownership and upgrades

Packages record the files they own. During an update, files which were owned by
that package in the previous version but are no longer part of it are removed,
provided no other installed package owns the same path.

Configuration/state are never package-owned:

```text
/etc/machine.lua
/etc/profile.lua
/etc/services/
/etc/systemd/
/etc/modules/
/var/lib/<component>/
/run/systemd/
/var/lib/storage/
/var/log/
```

This permits binary/package refactors without leaving obsolete executable files
behind.

## Installer

`install.lua` is a bootstrapper:

1. choose or reuse a preset;
2. bootstrap the current package manager;
3. install the preset root;
4. resolve/install dependencies;
5. preserve local identity/profile/state;
6. refresh version metadata.

The selected compatibility preset is stored in:

```text
/etc/preset
```

Normal refresh:

```text
install
reboot
```

or:

```text
pkgctl update
reboot
```


Packages may declare a first-run configurator. For example
`pkgctl install service.display` downloads the service/module dependency
closure and then invokes the display configurator unless `--no-config` is
specified.


## Migration independence

Package updates are not used as migration steps. The package manager installs
the current file set, while the migration engine converges recognized legacy
filesystem layouts directly to the current schema. This allows a machine to
jump from an old deployment to the current package set without installing each
intermediate release.
