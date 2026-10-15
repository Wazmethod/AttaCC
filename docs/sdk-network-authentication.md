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
- `textutils.sha256` support on the target CC runtime must be confirmed
  during compatibility validation.

## Next steps

Finish converting Master/Pocket/Web to descriptor-driven SDK messaging,
provide explicit migration/disable switch for legacy commands, migrate
telemetry/events and app boot lifecycle, and then run machine-level parity
testing once the SDK port is complete.
