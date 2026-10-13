# Package manager

AttaCC packages are declared in `packages/manifest.lua`.

## Commands

```text
pkgctl list
pkgctl status
pkgctl show <package>
pkgctl install <package>
pkgctl update
pkgctl prune
pkgctl configure <package>
```

## Package model

The main package families are:

```text
runtime.package-manager
core.runtime

module.network
module.display
module.storage-client
module.storage-server

app.steamplant
app.master
app.pocket
app.workstation
app.controller

preset.*
```

Applications own their machine-specific files and depend on reusable modules.
Presets are thin root bundles.

## Explicit roots

Packages installed directly are explicit roots. Dependencies are retained only
while reachable from an explicit root.

`pkgctl prune` recalculates this closure and removes orphan packages/files.

It also removes recognized legacy runtime paths left by versions prior to the
native AttaCC architecture.

## Optional capabilities

Capabilities which are not universally required should be installed explicitly.

Example:

```text
pkgctl install module.storage-server
```

A Master without this package remains a valid Master.
