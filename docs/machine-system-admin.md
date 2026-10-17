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
