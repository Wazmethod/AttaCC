# Package manager

The package manager removes the static file-list problem from `install.lua`.

## Model

Packages are declared in:

```text
packages/manifest.lua
```

The local registry is:

```text
.infra/packages.json
```

A package contains:

- a name;
- a kind (`runtime`, `preset`, `service`, `module`);
- dependencies;
- source -> destination file mappings.

Example dependency chain:

```text
preset.supervisor
  -> runtime.package-manager
  -> service.shared-storage-client
  -> service.shared-storage-server
```

## Commands

```text
pkgctl list
pkgctl status
pkgctl install <package>
pkgctl update
pkgctl update <package>
```

Packages explicitly installed by the operator are marked as roots. `pkgctl
update` resolves those roots again and refreshes all dependencies.

## Installer behaviour

`install.lua` is now a bootstrapper:

1. choose or reuse the machine preset;
2. download the current `pkgctl.lua`;
3. install the preset root package;
4. resolve and install dependencies;
5. preserve identity/profile files;
6. refresh project version metadata.

The selected compatibility preset is stored in:

```text
.infra/install-preset
```

Therefore, after the first migration to the package system:

```text
install
reboot
```

is sufficient for a normal full update.

## Adding a new module or service

Add a package to `packages/manifest.lua` and make the appropriate preset or
module depend on it. There is no second hard-coded download list to maintain.

Local files such as `machine.local.lua`, `profile.local.lua`, tokens and
runtime state must never be package-owned.
