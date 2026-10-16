# AttaCC V1.1 — simple Minecraft network mode

**Default: no `/etc/sdk-auth.lua` required for discovery, snapshots and events.**
Computers only need compatible wireless modems and the same `network` in
`/etc/machine.lua`. Sender keys are taken automatically from the machine
identity; no secret exchange or cross-machine peer configuration is needed
to monitor machines in the Minecraft world.

A peer entry with `events=true` or `snapshots=true` still requires valid
signed traffic from that specific sender. Other unconfigured peers use LAN
mode. Commands that control machines remain protected separately: they are
not enabled by LAN mode and still need explicit authorization.

**LAN mode is not authenticated.** A computer that can transmit on these
channels can forge a hostname, metrics or events. Do not use this information
alone to authorize physical control or perform administrative actions.

## Simplified trusted-machine CLI

The SDK runtime ships `authctl.lua`. Authentication remains mandatory for
remote commands; only command-by-command ACL management is removed.

On the **destination** (for example SteamPlant), run:

```text
authctl allow main:pocket
```

On the **client** (for example Pocket), run:

```text
authctl client
```

Enter the **same strong shared secret of 32+ characters** locally in both
commands. The destination uses `peer.allControls=true`, which authorizes
*all remotely exported controls* for that machine identity after verifying its
signed request. All existing local hardware interlocks and confirmation
requirements remain in force. Never grant this on live industrial machinery
without understanding the effects of every exported action.

`authctl status` shows configured peer names but never secrets.
`authctl revoke main:pocket` removes a trusted source. The commands
write `/etc/sdk-auth.lua` locally and are not included in GitHub/package files.
For a client that controls several targets, each target must have the
corresponding client secret (a single current Pocket SDK client secret is
shared across targets if they authorize it).

A machine key alone is NOT an authentication credential. The CLI still
requires entering a secret on both sides: no insecure automatic trust based
solely on a public hostname/key.

## Simple setup

For each CC, keep its existing `/etc/machine.lua` (including any other
settings). Give each machine a unique `key` and use the same `network`.
With no machine file, the SDK falls back to `cc:<computerId>` and
`network="default"`. The shell commands are unchanged:

```text
pkgctl update core.runtime
pkgctl update app.master_preview
appctl master_preview
```

The following sections document optional signed controls and authenticated
peers. They are **not prerequisites** for the read-only Master/Pocket test.

---

# AttaCC V1.1 — signed SDK control transport

This is a development-branch protocol. Deploy no actuator controls until
all client/server paths and safeguards have been validated.

## Envelopes

Request: `attacc.sdk.command.v1`. Fields: `app`, `control`,
`origin`, `target`, `network`, unique `id`, UTC millisecond
`timestamp`, `args` (map), and `auth={version=1,signature=<hex HMAC>}`.

ACK: `attacc.sdk.ack.v1`; includes the original request identifiers,
control, origin, target, network, result and timestamp with an HMAC signature.

SDK channels on SteamPlant: control **4257**, ACK **4258**.
Legacy channels 4245/4246 remain unchanged during the migration.

## Manual provisioning

Create `/etc/sdk-auth.lua` on the **generator**, separately from installed
packages. Assign a distinct cryptographically random key (at least 32 random
bytes, represented as a long string) to every client. Do not commit it.

```lua
return {
    legacyCommands = true, -- set false ONLY after every client is migrated
    peers = {
        master = {
            enabled = true,
            key = "REPLACE_WITH_A_LONG_RANDOM_SECRET_PER_PEER",
            controls = {
                procedure = true,
                abort = true,
                disarm = true,
                motor_stop = true,
            },
        },
        pocket = {
            enabled = false,
            key = "A_DIFFERENT_RANDOM_SECRET_FOR_POCKET",
            controls = { abort = true },
        },
    },
}
```

On the **Master** or **Pocket** computer, create its own `/etc/sdk-auth.lua`
with a matching private key and exact sender origin:

```lua
return {
    client = {
        enabled = true,
        origin = "master", -- or "pocket"
        secret = "SAME_SECRET_AS_GENERATOR_PEERS_MASTER",
    },
}
```

Without `client.enabled=true`, clients use the original wire format.
Once enabled, a bad SDK client configuration fails closed rather than
silently downgrading a command to the legacy format.

## Security details and limitations

- Requests are MACed with HMAC-SHA256 over a deterministic encoding of
  command fields; ACKs are signed separately.
- Unknown or disabled peers, invalid signatures, unauthorized controls,
  wrong targets/networks, expired timestamps and repeat request IDs are
  rejected.
- Only the **specific allowlisted controls** can be remotely invoked.
- Clocks need to be approximately synchronized (SDK request age: 10 seconds).
- Idempotency is bounded by an in-memory TTL; it is not persistent over reboot.
  Crash/restart and retries still require operational safety review.
- HMAC secrets must be independently provisioned and rotated. Redstone
  computer IDs and `origin` strings alone are **not authentication**.
- This scheme is not a secure key-exchange protocol: it assumes the shared
  secrets were distributed securely and kept private. It does not encrypt
  telemetry or commands.
- The legacy network path remains available unless the generator sets
  `legacyCommands=false` in `/etc/sdk-auth.lua`. It is **not secured by these
  SDK checks**. Do not interpret adding SDK authorization as protecting
  legacy clients. The legacy path must be removed or explicitly locked
  down before release.
- Hashing is provided by the bundled pure Lua `lib.sha256` module using
  CraftOS `bit32`; it does not rely on an undocumented `textutils.sha256` API.
  Cryptographic test vectors and end-to-end tests remain required before release.

## Next steps

Finish converting Master/Pocket/Web to descriptor-driven SDK messaging,
provide explicit migration/disable switch for legacy commands, migrate
telemetry/events and app boot lifecycle, and then run machine-level parity
testing once the SDK port is complete.
