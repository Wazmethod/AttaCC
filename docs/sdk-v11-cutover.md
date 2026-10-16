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

## Consolidation checks — 16 October 2026

- Native event frames are signed and verified against an opt-in per-peer events ACL. A bounded in-memory replay filter now suppresses duplicate signatures for 30 seconds. The filter is **not durable** across reboot; clock synchronization and key management are still required.
- Node discovery binds the announced node key to the authenticated event origin; a peer cannot advertise another machine key without possessing that peer's signing identity. Announcements remain informational and cannot authorize commands.
- SDK snapshot publication now returns modem transport failures rather than silently reporting success. SDK snapshots remain **unsigned**, and should not be considered verified telemetry; secure snapshot authentication and payload size limits are pending.
- Storage requests fail closed if backend initialization fails, a write is missing a value, or an operation produces an absent result. Missing get keys are currently treated as errors rather than an ambiguous JSON null. The storage backend still lacks per-namespace/per-key request authorization, and `storage_request` permissions currently apply at the control level. **Do not enable Storage writes in production.**
- Added Lua tests for signed event verification, node identity binding and basic storage input validation. GitHub CI and Minecraft/CraftOS integration results must be confirmed separately.

## Storage peer / namespace ACL (SDK preview)

Storage commands require **two independent gates**: authenticated SDK control permission `peers[origin].controls.storage_request=true` in local `/etc/sdk-auth.lua`, and the storage host's application configuration `storageService.enabled=true`, `storageService.actions[action]=true`, plus `storageService.namespaces[origin][namespace][action]=true` for list/get/set/delete. Global discovery operations ping/namespaces instead require `storageService.namespaces[origin].ping=true` or `.namespaces=true`. No wildcard grants are interpreted. Missing peer identity, missing namespace rule or missing action deny by default. The authenticated origin is scoped to the remote control invocation and cleared even when the control raises an exception. These rules live only on the storage host; clients cannot submit their own grants.

Example host configuration override in `/etc/attacc/apps/storage_agent/config.lua` (confirm config path through `appctl` before applying):

```lua
return {
  storageService = {
    enabled = true,
    actions = {ping=true,namespaces=true,list=true,get=true,set=false,delete=false},
    namespaces = {
      master = {ping=true,namespaces=true,["attacc.events"]={list=true,get=true}},
    },
  },
}
```

The Storage SDK still uses a single remote control ID, so this application ACL is essential, not optional. ACL enforcement and associated tests have not been validated in CraftOS. Writes must remain disabled in live environments until persistence, replay and recovery tests are complete.

## Authenticated SDK snapshots

Snapshot broadcasting now requires a local SDK client identity whose `client.origin` exactly matches `machine.key`. Receivers require a matching `peers[machine.key]={enabled=true,key=<secret>,snapshots=true}` authorization in their own private `/etc/sdk-auth.lua`. The HMAC covers the descriptor, machine, network, module, schema and timestamp, with a 32 KiB canonical payload bound and 10-second freshness window. Tampered and unsigned frames are rejected before any Master/Pocket/Workstation/WebBridge SDK snapshot callback is invoked. Duplicates are suppressed by a volatile signature cache. This is **not encryption**, does not provide persistence across restarts, and does not establish a trusted Web server role. Missing authentication configuration intentionally prevents snapshot publishing and receiving.

## Practical Minecraft scope — 16 October 2026

AttaCC is a CC:Tweaked system for Minecraft, not a general enterprise control platform. Keep SDK network, snapshots, UI and Storage APIs shared, but prefer a small number of clear machine roles and game-friendly defaults. Avoid adding persistent PKI, an external database, service meshes or complex policy engines solely to improve the prototype. Preserve the existing machine interfaces and only expose remote controls after basic gameplay parity testing. Today's usability corrections: replay cache expiry also occurs on snapshot-only traffic, Pocket resets a removed selected command, and Workstation does not repeatedly poll an empty Storage destination. These are source-level improvements; CraftOS verification remains outstanding.

## Default Minecraft LAN profile (October 2026)

For normal CC:Tweaked dashboards, SDK snapshots, node discovery and named
events are keyless by default. Each computer needs only a wireless modem,
a unique machine key and matching logical network. If `/etc/machine.lua`
is not configured, the physical computer ID and `default` network provide
fallback values. `/etc/sdk-auth.lua` is optional for receiving telemetry and
discovery; intentionally protected peers still enforce signatures.

Remote controls, Storage writes and node administration are **not unlocked**
by keyless telemetry. Signed controls remain disabled without deliberate
per-machine setup. Do not treat open-LAN telemetry as authenticated.

The older sections documenting required signing for all snapshots/events
describe the previous strict preview, not the new default LAN profile.
