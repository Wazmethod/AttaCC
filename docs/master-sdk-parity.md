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
| MACHINE DATA | Native SDK metric widgets and category/page selection | Partial: first three values and grouped MACHINE navigation |
| MACHINE GRAPHS | Historical rolling graph series, category pagination | Partial: per-source history and two rendered graph series; category pagination remains missing |
| MACHINE CONTROLS | Authorized signed commands, confirmations, retries, ACK | Partial: all exported remote controls paged three at a time, SDK signed client and ACKs; locked by default; categories and end-to-end tests missing |
| EVENTS | Last 100, chronological, severity, machine navigation | Partial: last 100 restored/saved through SDK local state, three recent lines shown; remote storage, severity filtering and navigation missing |
| NETWORK | Nodes, conflicts, online/stale | Passive discovery implemented; full screen missing |
| HOME STORAGE | Existing storage backend and remote persistence | Partial: live local runtime service status; remote Storage not yet migrated |
| HOME WEB | WebBridge connected/disabled/degraded and metadata | Missing |
| Master terminal HOME/NODES/STORAGE/DISPLAY | SDK maintenance pages with same navigation | Missing |
| Pocket broadcast | Existing pocket status contract | Missing |
| WebBridge WebSocket + command relay | Native SDK WebSocket service | SDK event-driven WebSocket transport implemented; protocol forwarding not yet migrated |
| WebBridge node admin/reboot/acks | Native SDK authenticated admin service | Missing |
| WebBridge network labels | Native SDK configuration and reporting | Missing |
| WebBridge UI/config management | Native SDK maintenance screen | Missing |
| Network protocol compatibility | Existing peers and web service remain supported | Not validated |
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
