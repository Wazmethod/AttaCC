# Package manager

`pkgctl` remains the deployment layer of the native runtime.

Packages are declared in:

```text
packages/manifest.lua
```

The local registry is:

```text
/var/lib/pkgctl/packages.json
```

## Package kinds

```text
runtime  shared libraries/tooling
module   reusable I/O/API capability
service  background capability or compatibility service package
preset   default package recipe for one usage
```

A preset is a package set, not a runtime process manager.

## Presets

```text
collector   -> preset.infrastructure-node
controller  -> preset.automation-node
master      -> preset.supervisor
pocket      -> preset.portable-client
workstation -> preset.workstation
```

The selected preset is stored in `/etc/preset`. At boot, `startup.lua`
maps it directly to the corresponding application binary.

## Dependencies

Dependencies are recursively installed:

```text
pkgctl show <package>
pkgctl deps <package>
pkgctl install <package>
```

Explicitly installed packages remain roots for later `pkgctl update`.

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

## File ownership and upgrades

Package-owned files can be replaced or removed automatically when the manifest
changes. Local machine configuration and persistent state are kept separate.

Important local data includes:

```text
/etc/preset
/etc/machine.lua
/etc/profile.lua
/etc/webbridge.lua
/var/lib/<component>/
```

## Native-runtime transition

0.29 removes `service.remote-shell` from all standard preset dependency
closures. The package remains available for explicit compatibility installs.

The old service-runner compatibility files are still distributed where current
applications require their libraries, but `startup.lua` no longer launches
`init.lua` or a service graph.

This lets package/runtime cleanup happen incrementally without changing the
production SteamPlant logic and the boot model in the same step.
