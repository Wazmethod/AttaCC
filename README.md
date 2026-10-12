# CC Infrastructure Control

Distributed supervision and automation framework for **CC:Tweaked**.

The Create steam plant is the first production application of the framework,
not the architectural boundary of the project.

Current development version: **0.27.0-dev**.

## Runtime model

```text
package / preset
    -> services (*.service)
        -> binaries/processes
            -> modules (*.mod)
                -> logical I/O / APIs
                    -> Minecraft peripherals
```

The distinction is intentional:

- `*.service`: runtime responsibility/lifecycle;
- binary: actual CraftOS program/process/tab;
- `*.mod`: reusable functionality/API/business logic;
- preset: default package recipe, not machine identity.

Multishell tabs use binary names such as `sshd`, `displayd`,
`workstationd`, `collectord` and `supervisord`. Modules do not create tabs
merely because they are loaded.

See [docs/architecture.md](docs/architecture.md).

## Installation and packages

Bootstrap once and then:

```text
install
reboot
```

Useful package commands:

```text
pkgctl list
pkgctl status
pkgctl show service.display
pkgctl install <package>
pkgctl configure <package>
pkgctl update
```

Presets only select defaults. Additional capabilities can be installed later.
For example, to add display support to another compatible machine:

```text
pkgctl install service.display
displayctl use auto
reboot
```

Dependencies are installed automatically and explicit extra packages remain
update roots.

Current compatibility presets:

```text
collector   -> preset.infrastructure-node
controller  -> preset.automation-node
master      -> preset.supervisor
pocket      -> preset.portable-client
workstation -> preset.workstation
```

See [docs/operations/package-manager.md](docs/operations/package-manager.md).

## Runtime inspection

```text
systemctl list
systemctl status init.service
systemctl status display.service
systemctl cat display.service
systemctl edit display.service

ps

lsmod
```

`systemctl` shows services, `ps` shows actual running binaries/tabs, and
`lsmod` shows loaded/observed modules.

## Shared network storage

```text
storagectl ping
storagectl ns
storagectl set demo answer 42
storagectl get demo answer
storagectl list demo
```

The supervisor provides the shared namespaced key/value storage service.

## Remote administration

```text
ssh --scan
ssh <hostname>
machinectl hostname [new-hostname]
```

Remote commands stream terminal output/input between machines.

## Display

Display is split into:

```text
module.display
    -> lib/display_api.lua

service.display
    -> displayd.lua
    -> displayctl.lua
```

Business modules publish what should be displayed; `displayd` owns the
monitor and rendering/view selection.

Useful commands:

```text
displayctl detect
displayctl status
displayctl use auto
displayctl views
displayctl select <view>
```

## Shell environment

```text
profilectl edit
cat <file>
less <file>
ps
lsmod
ssh <hostname>
systemctl ...
machinectl ...
pkgctl ...
storagectl ...
displayctl ...
```

System layout now follows a small Linux/systemd-style hierarchy:

```text
/etc/infra/
  machine.lua
  profile.lua
  services/*.conf.lua
  systemd/*.service.lua        local unit overrides
  modules/*.mod.lua            local module overrides

/usr/lib/infra/
  systemd/*.service.lua        package-owned units
  modules/*.mod.lua            package-owned descriptors

/var/lib/infra/
  packages.json
  runtime/
  state/
  storage/

/var/log/infra/
  journal.log
  services/*.log
```

Legacy `.infra/` configuration/state is migrated automatically during boot.

## Development

- [Architecture](docs/architecture.md)
- [Module development](docs/module-development.md)
- [Machine identity](docs/concepts/machines.md)
- [Runtime services](docs/concepts/services.md)
- [Application modules](docs/concepts/modules.md)
- [Profiles and logical I/O](docs/concepts/profiles-and-io.md)
- [Installation and migration](docs/installation.md)
