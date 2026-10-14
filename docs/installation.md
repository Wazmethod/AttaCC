# Installation

## First install

Run the bootstrap installer on the CC computer:

```text
install
```

The installer selects an AttaCC preset, installs its dependency closure,
preserves machine identity/profile configuration and writes `/etc/preset`.

Available presets:

```text
steamplant  -> preset.steamplant  -> app.steamplant
master      -> preset.master      -> app.master
pocket      -> preset.pocket      -> app.pocket
workstation -> preset.workstation -> app.workstation
```

Then reboot:

```text
reboot
```

## Migrating to the 0.31 native layout

0.31 removes the old preset/package names completely. On a computer installed
before 0.31, run the installer once instead of starting with `pkgctl update`:

```text
install
pkgctl prune
reboot
```

Choose the equivalent new preset when prompted. The installer preserves:

```text
/etc/machine.lua
/etc/profile.lua
/etc/webbridge.lua
```

where applicable.

After that one-time migration, normal updates use:

```text
pkgctl update
reboot
```

## Identity and profile

Machine identity is stored in:

```text
/etc/machine.lua
```

Per-machine application configuration is stored in:

```text
/etc/profile.lua
```

The active preset is stored in:

```text
/etc/preset
```

## Optional storage host

Storage is not implied by the Master preset.

To host the shared store:

```text
pkgctl install module.storage-server
```

Clients use `module.storage-client`.

## Runtime layout

```text
/run/attacc
/var/lib/pkgctl
/var/lib/attacc
/var/lib/storage
/var/log/attacc
```


## Optional central configuration

After a Storage host is available, enable synchronized configuration on each
machine:

```text
profilectl storage-sync
```

Then seed or refresh the central copy with:

```text
profilectl push
```

The normal application-specific `profilectl` assistants continue to edit the
local profile and automatically push their changes when synchronization is
enabled.

To edit another synchronized machine from any AttaCC client:

```text
profilectl machines
profilectl remote <machine-key> machine
profilectl remote <machine-key> profile
```

## Installer and Storage host corrections (0.31 dev)

The installer now collects machine identity **once**. Its optional app configuration phase opens `profilectl config inter`, not `profilectl init` (which remains a standalone first-run wizard). The effective identity network belongs to `/etc/machine.lua`; `profilectl config inter` displays that value instead of a preset's network default.

When `module.storage-server` is installed, `storagectl hosts` also lists its **local backend**, even if the host cannot hear its own wireless broadcast. Commands such as `storagectl ping` and `storagectl ns` can use that local backend automatically if no remote target is chosen; this does not enable config synchronization. To enable syncing the host's own machine config, explicitly use:

```text
storagectl hosts
storagectl use <this-machine-key>
profilectl push
```

The client/server module uses the same `storagectl` binary; no separate local CLI needs to be installed.

## Master WebBridge installation

`webbridge.lua` and `webbridgectl.lua` are installed by **app.master**. There is no separate `module.webbridge` package. On the Master:

```lua
cp web.example.lua /etc/webbridge.lua
edit /etc/webbridge.lua
```

Set the `url` (e.g. `ws://<docker-host>:8080/ws/machine`) and `machineToken` to the backend's **MACHINE_TOKEN**. Use `wss://` when served behind HTTPS/TLS. On the Docker host, configure `web/.env` from `web/.env.example`, with strong non-default `MACHINE_TOKEN` and `ADMIN_TOKEN`, then run `docker compose up -d --build` from the `web/` directory.

Restart the Master to launch WebBridge. `webbridgectl configure` manages presentation labels after the connection file exists; it does **not** configure the WebSocket URL or token by itself.

Client UI labels marked ACTIVE based on configured target indicate **configuration**, not necessarily live connectivity. Use `storagectl ping` to check reachability.
