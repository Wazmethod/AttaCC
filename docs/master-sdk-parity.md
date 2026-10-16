# Master -> SDK V1.1 : functional and visual parity

Reference: `apps/master/main.lua`, `modules/dashboard_view_graphics.lua`,
`modules/dashboard_view_text.lua`, `apps/master/webbridge.lua` on this repository.

The original Master UI is **not** a generic overview. Its visible hierarchy is:

- **HOME**: MACHINES, RECENT EVENTS, STORAGE, WEB, network overview
- **MACHINE**: machine selector; tabs **DATA**, **GRAPHS**, **CONTROLS**;
  individual pagination and categories inside each tab
- **EVENTS**: chronological log; select machine from event
- **NETWORK**: discovered nodes and status

The local terminal has another set of screens: HOME, NODES, STORAGE,
DISPLAY. The WebBridge also has its own local console and networking tools.

## Migration acceptance matrix

| Existing behavior | Native SDK target | State |
| --- | --- | --- |
| HOME sections and order | SDK composite layout grouped as original | Not yet equivalent: SDK flat widget grid |
| Machine selector | SDK source selection, stale handling | Partial: monitor source arrows on MACHINE DATA and console source rotation |
| MACHINE DATA | Native SDK metric widgets and category/page selection | Partial: pageable data exports (3 per page) and grouped MACHINE navigation |
| MACHINE GRAPHS | Historical rolling graph series, category pagination | Partial: per-source rolling histories; pageable graph exports (2 per page), category grouping still missing |
| MACHINE CONTROLS | Authorized signed commands, confirmations, retries, ACK | Partial: all exported remote controls paged three at a time, SDK signed client and ACKs; locked by default; categories and end-to-end tests missing |
| EVENTS | Last 100, chronological, severity, machine navigation | Partial: last 100 restored/saved through SDK local state, three recent lines shown; remote storage, severity filtering and navigation missing |
| NETWORK | Nodes, conflicts, online/stale | Passive discovery implemented; full screen missing |
| HOME STORAGE | Existing storage backend and remote persistence | Partial: live local runtime service status; remote Storage not yet migrated |
| HOME WEB | WebBridge connected/disabled/degraded and metadata | Missing |
| Master terminal HOME/NODES/STORAGE/DISPLAY | SDK maintenance pages with same navigation | Missing |
| Pocket broadcast | Existing pocket status contract | Missing |
| WebBridge WebSocket + command relay | Native SDK WebSocket service | SDK event-driven WebSocket transport implemented; protocol forwarding not yet migrated |
| WebBridge node admin/reboot/acks | Native SDK authenticated admin service | Partial: dedicated node_agent preview with signed controls and post-ACK actions; Web integration and action completion status missing |
| WebBridge network labels | Native SDK configuration and reporting | Missing |
| WebBridge UI/config management | Native SDK maintenance screen | Missing |
| SDK-only network cutover | Migrate every peer and Web server to native SDK frames | Pending; legacy peers deliberately not bridged |
| Security checks | No legacy fallback on bad SDK credentials | SDK remote client enforces this |
| In-game integration | Test only after full parity | Not started |

**Do not replace `preset.master` or `app.master` until every entry is
implemented and verified.** The `app.master-sdk-preview` candidate is
isolated and cannot issue production commands.

The present candidate's HOME/MACHINE/GRAPHS/CONTROLS/EVENTS/NETWORK
views are structural placeholders; they do not yet reproduce the original
grouping, tabs or real event/graph/storage/web content.

## SDK navigation update

Graphics monitor now supports parent views. Master displays MACHINE with DATA / GRAPHS / CONTROLS as sub-tabs, and local-only previous/next source buttons on DATA. Full machine list, page-specific categorical controls, text-mode parity and panel composition remain pending.

## Remote control preview safety

Master SDK candidate has three selected-app remote control slots. Only controls declared `remote=true` and currently enabled in the received SDK snapshot qualify. Execution is disabled by default (`supervision.allowRemoteCommands=false`), sources must be fresh, monitor interaction requires confirmation, and SDK signing/ACK checks are required. The UI still lacks the historical full catalog/category control picker. Do not enable during development; no production test has been run.

## Persistence and control paging

Master preview saves the latest 100 sanitized event strings through `app:state("events", {entries=...})` at most once per 30 seconds during runtime updates, and restores them at startup. This is SDK local persistence, **not** parity with the old shared Storage backend. Unsaved events may be lost on abrupt shutdown. The remote control catalog is now pageable three controls at a time; changing source or page clears any pending touch confirmation. Full historical category semantics remain outstanding.

## SDK service transport stage

The SDK host now owns an optional event-driven WebSocket service (`sdk_websocket.lua`), which requires explicit URL/token options. This is a transport primitive only: no old WebBridge forwarding, network labels, admin requests, node heartbeat, or server protocol have been moved yet. Master HOME can query local runtime status for `app:webbridge` and `module:network.storage`, but this is not an end-to-end health check. The existing Master and WebBridge remain unchanged.

## Native WebBridge preview (read-only forwarding)

The separate `app.webbridge-sdk-preview` candidate uses `sdk_websocket` and `sdk_webbridge_adapter` to relay SDK snapshots (including compatibility telemetry), legacy telemetry/events, and node status/heartbeat in the existing Web JSON envelope. The candidate deliberately **does not** accept server-sent commands, node admin/reboot, or relay ACKs; connection configuration is SDK app-specific (`/etc/attacc/apps/webbridge_preview/config.lua`) rather than the existing `/etc/webbridge.lua`. Network label management, system snapshot and complete WebBridge maintenance UI remain pending. No live WebSocket test has been run; do not switch the existing WebBridge to this candidate yet.

## SDK-only migration decision

The wire compatibility adapter has been removed. The new WebBridge candidate forwards native SDK snapshots as-is and uses an SDK node heartbeat. The Web backend and all applications must consume SDK contracts before cutover. Legacy behavior and layout are functional acceptance requirements, but legacy wire formats are not retained. This preview is not compatible with the old Web backend and must not be deployed to production.

## Native SDK application networking

Network events use `app:onNetwork("app.event", callback)` and
`app:publishNetwork("app.event", payload)`, with the SDK transport owning
the physical modem channel and event loop. The wire message type is
`attacc.sdk.event.v1`. Master and WebBridge previews subscribe through
this API; Master no longer subscribes to legacy event channels.

**Security gate:** named SDK events currently have network filtering and
basic structure checks, but not cryptographic message authentication.
They are suitable for informative telemetry/events only; never use them
to authorize remote operations. Signed `sdk_commands` remains required
for commands, and origin authentication/replay defenses must be added to
the event protocol before treating events as trustworthy.

Remaining migration: remove the old eventChannels/onNetworkEvent hooks,
move all producers to SDK publication, and provide SDK public APIs for
node discovery and WebSocket send/receive. The legacy app packages remain
untouched until full parity and integration testing.

## Unified application-facing SDK APIs

- `app:publish()`: publishes the app descriptor locally; SDK host handles scheduled snapshot broadcast.
- `app:emit(topic, payload)`: local process event bus.
- `app:publishNetwork(topic, payload)` and `app:onNetwork(topic, handler)`: SDK network events; not an authenticated control plane.
- `app:nodes()` and `app:node(key)`: passive SDK-discovered node information (requires `discoverNodes=true`).
- `app:remoteCommand(machine, appId, control, args, callback)`: signed SDK remote command request with ACK callback (requires `remoteClient=true` and SDK credentials).

Master SDK now calls these public APIs instead of reaching into the SDK remote client and discovery service. The signed client origin is taken from SDK auth configuration, not hard-coded to Master. No in-game integration tests have been run.

## Web SDK command relay

The WebBridge SDK preview supports an opt-in command path from Web messages through app:remoteCommand to authenticated ACK callbacks. Disabled by default. It requires a per-application allowlist, valid command fields and recent timestamps; request IDs are tracked to reject repeats. Production use still requires server trust validation, role-based authorization, durable replay protection and tests.

## SDK Web command gateway integrated

The SDK host now initializes and ticks the SDK Web command gate. WebBridge calls `app:webCommand()` and no longer validates application/target/control policies itself. The bridge config uses `bridge.commandRules[appId].targets[machineKey].controls[controlId]=true` and `bridge.allowRemoteCommands=false` by default. The gateway requires the request network to match and delegates signed radio requests and verified ACKs to `app:remoteCommand()`. This is untested in CraftOS and not ready for production: server-side identity/role authorization, long-lived replay protection and secure deployment remain outstanding.

## SDK-native node discovery

The SDK host now publishes `node.status` through `app:publishNetwork()`, using the payload type `attacc.sdk.node.v1`. `discoverNodes=true` subscribes via `app:onNetwork()` before opening the SDK transport, and `sdk_nodes` only accepts the native node payload. WebBridge subscribes to the same SDK topic and forwards these native node envelopes to the Web server. No application needs to open node modem channels. Note: SDK network events are currently network-scoped but unauthenticated; announcements are discovery hints, **not proof of node identity or authorization**. Legacy node administrative actions/reboot have not yet migrated, and node data must not be used to authorize them until signed node identity verification is implemented.

## 2026-10-16 — SDK node administration phase

The core runtime now supports optional `nodeAdmin={enabled=false,actions={package_update=false,package_configure=false}}` lifecycle settings. The SDK host registers remote controls `node_package_update` and `node_package_configure`, both disabled unless explicitly authorized. Commands follow the existing signed SDK command transport and require per-peer control ACLs. The package argument is validated before invoking the existing maintenance executor. Reboot is deliberately excluded until deferred execution after signed ACK delivery is implemented. Integration and in-game tests have not been performed.

## Current consolidation pass

See `docs/sdk-v11-cutover.md` for the SDK API inventory and coordinated deployment gates. DATA and GRAPHS now page all selected-source exports; the graphics renderer supports view-scoped page controls. A dedicated node agent and post-ACK maintenance scheduling have been added. GitHub Actions runs Lua syntax checks and node admin/Web command contract tests. No CraftOS deployment or visual parity validation has occurred.
