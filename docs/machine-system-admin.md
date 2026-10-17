# Machine-wide administration (SDK v1.1)

Runtime system commands are automatically registered by `core/sdk_host.lua`
whenever an AttaCC app runs. No extra daemon or tab is launched. Without
a running app, commands cannot be received.

System operation policy is stored locally in `/etc/attacc/system.lua`,
edited using `appctl config system`. Example:

```lua
return {
    admin = {
        enabled = true,
        actions = {
            reboot = true,
            package_update = false,
            package_configure = false
        }
    }
}
```

This is separate from `/etc/sdk-auth.lua`, which identifies authorized
command peers using HMAC; both requirements must pass. The runtime reads
system policy at application launch. An absent or malformed policy denies
all system actions. App-specific `admin.*` keys no longer grant permissions.

Upgrade: `pkgctl update core.runtime`, configure the new system policy on
each destination, and restart its running application. Previously granted
application-level reboot permissions are not migrated automatically.
`node_reboot` remains UI-hidden and accessible via MACHINES only; it
requires the signed command's `{confirm=true}` argument and the client
double-tap confirmation.

Note: this file is local to each computer and must not be committed with
machine-specific policy or secrets.

## Editing physical display preferences

`appctl config system` also exposes machine-level display hardware settings:
`display.monitorName`, `display.textScale`, `display.touchProfile`,
`display.touchFlipX`, `display.touchFlipY`,
`display.touchInsetX`, and `display.touchInsetY`.

Application layout settings such as `display.viewMode`, `display.mode`,
and `display.confirmControls` stay application-specific.

Boolean fields in `appctl config` accept numbered choices:
`1` for true/enabled, `2` for false/disabled (the literal values
are still accepted for compatibility). False settings display correctly.

Legacy application monitor settings remain effective until the matching
machine-wide property is explicitly written in `system.lua`.
The new file is per-machine and must not be committed with user overrides.

## System administration CLI

`systemctl status` shows machine identity and local system administration
permissions. `systemctl config` opens the machine-wide editor, backed by
`/etc/attacc/system.lua`. Identity operations are preserved as
`systemctl init`, `hostname`, `export`, `import` and `reset`.
`machinectl` is only a backwards-compatible forwarding alias.

`appctl config <app-id>` configures applications;
`ioctl` manages hardware and `authctl` signed-command trust.
The interactive config editor now returns to the same category after
saving/canceling a field rather than returning to the root category menu.
