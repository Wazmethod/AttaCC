# SDK V1.1 — coordinated migration checklist

Development branch: `feature/v1.1-sdk-unification`. **No live cutover until parity review.**

## Application contract

| Requirement | SDK interface |
| --- | --- |
| Export application state | `app:data`, `app:set`, `app:publish`; host broadcasts snapshots |
| Publish local event | `app:emit` |
| Publish network event | `app:publishNetwork` |
| Subscribe to network event | `app:onNetwork` |
| Observe SDK snapshots | `app:onSnapshot` |
| Discover machines | `app:nodes`, `app:node` |
| Send signed remote command | `app:remoteCommand` |
| Asynchronous signed storage operation | `app:storageRequest(target,action,namespace,key,value,callback)` |
| Send/receive WebSocket JSON | `app:webSend`, `app:onWebMessage`, `app:webStatus` |
| Gate Web-originated command | `app:webCommand` |
| Act after signed ACK transmit | `app:deferAfterAck` (inside authenticated command only) |
| Register node maintenance controls | SDK Host `nodeAdmin` option |

No application should own `modem.open`, `modem.transmit`, `rednet`,
`http.websocket` or the CraftOS network event loop.

## Current migration inventory

- **SteamPlant:** SDK-native app composition; production behavior not revalidated.
- **Master:** isolated native preview; HOME and detail layout not yet equivalent.
  DATA, GRAPHS and CONTROLS now page the available SDK snapshot exports.
- **WebBridge:** isolated SDK-only preview, signed Web command gateway, native
  snapshot and event forwarding; Web server contract remains to migrate.
- **Node Agent:** new `app.node-agent-sdk-preview`, all admin actions disabled
  by default; update, configure and reboot are SDK remote controls.
- **Pocket:** new `app.pocket-sdk-preview` with snapshot inspection, paged metrics, node discovery and signed remote control candidate; historical Pocket display/navigation and complete capabilities remain to migrate. Old `app.pocket` untouched.
- **Workstation:** new `app.workstation-sdk-preview` with SDK node inventory, health and runtime summary; legacy console management, storage tree, device panels and original interactions remain to migrate. Old `app.workstation` untouched.
- **Storage:** native `app.storage-sdk-preview` now exposes signed `storage_request` controls for ping, namespaces, list, get, set, delete. `core/sdk_storage.lua` provides an asynchronous SDK client and Workstation preview reads namespaces through it. Legacy storage client and host remain deployed separately; history/permissions/parity, completion handling and Minecraft tests remain outstanding.
- **SDK network events/discovery:** transport and subscriptions implemented;
  signed origin authentication is now required; discovery remains informational, not an authorization decision.

## Security and reliability gates

1. Never enable node admin without SDK peer ACL, unique secrets and verified
   origin/target permissions.
2. `node_reboot` requires both explicitly enabled action and
   `args.confirm=true`; runtime defers invocation until after signed ACK
   transmission. Transmission is **not** proof of receipt.
3. Package maintenance ACK means **scheduled/accepted**, not completed.
   Completion requires a separate signed status event or follow-up snapshot.
4. Web command gate requires explicit app/target/control rules; additional
   Web server identity, role authorization and durable replay protection
   are still needed.
5. WebSocket enforces `wss://` by default; `allowInsecure=true` is only
   appropriate on a deliberately isolated development endpoint.
6. SDK named network events and node announcements still lack cryptographic
   authentication. They cannot grant permissions or confirm physical actions.
7. Confirm behavior and layout in CraftOS after all applications use SDK
   contracts; only then switch preset aliases and retire legacy components.

## Automated checks

Workflow: `.github/workflows/sdk-lua-checks.yml`.
It runs `luac5.3 -p` on Lua sources and
`lua5.3 tests/sdk_v11_admin_spec.lua`. This cannot exercise real modems,
WebSocket server integration, monitor hitboxes, persistence under sudden
shutdown or real package-manager operations.

## SDK-native Storage contract (in development)

The SDK Storage Agent is **disabled by default**. Enabling it requires an explicit configuration and a peer ACL allowing `storage_request`. Read and write operations require separate `storageService.actions` authorization on the agent. Values are returned as bounded JSON in signed `attacc.sdk.ack.v1` frames; the ACK HMAC now covers the value field. The application-facing `app:storageRequest(target, action, namespace, key, value, callback)` method is asynchronous. The callback receives `(success, decodedValue, error, ack)`. Existing backend persistence is reused; there is **no legacy network protocol adapter**. Signed argument canonicalization now supports bounded Lua arrays. This is not a drop-in replacement for the historical blocking `lib.storage_client` API. Server authorization, storage availability reporting, namespace access policies and live CraftOS/Web tests remain to be completed before cutover.

## Signed native network events (development)

Native `attacc.sdk.event.v1` frames are HMAC-SHA256 signed across topic, payload, origin, network and timestamp. The publisher requires `/etc/sdk-auth.lua` with `client={enabled=true,origin=<machine.key>,secret=<unique 32+ byte key>}`. Each receiver must define `peers[origin]={enabled=true,key=<same secret>,events=true,controls={}}`. Events fail closed when configuration is absent, the signature is invalid, the network differs or timestamps are more than ten seconds old. Discovery no longer accepts unauthenticated radio announcements through the SDK host. Receiver configuration is local and never distributed by package. This does not authenticate snapshots, provide durable replay protection, or authorize controls based on node announcements. No in-game testing has been performed.
