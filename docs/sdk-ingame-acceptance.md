# AttaCC SDK V1.1 — in-game functional acceptance

Branch: `feature/v1.1-sdk-unification`. **Preview only; do not replace live machine presets.**

## Preconditions and stop conditions

1. GitHub Actions SDK Lua checks all pass on the exact commit intended for testing.
2. Back up `/etc/`, application state, I/O mapping and existing software on every CC computer.
3. Use isolated test computers/modems and fake or physically disconnected actuators first.
4. Configure one independent secret per machine (32+ high-entropy bytes) in each computer's local `/etc/sdk-auth.lua`. Never commit credentials.
5. For signed events, ensure `client.origin` exactly matches machine key and receivers configure `peers[origin].events=true`. For controls, explicitly allow each peer/control. Configure Storage peer/namespace permissions independently.
6. Keep SteamPlant `commissioning.allowOutputs=false`, node admin disabled and Storage writes disabled until verified on a safe test installation.
7. **Stop immediately** for any unexpected redstone activation, missing interlock, unsigned control acceptance, wrong machine identity or unresolved identity conflict.

## Automated gates before game deployment

- `luac5.3 -p` for all Lua files.
- Run all `tests/sdk_v11_*_spec.lua` cases.
- Confirm SDK-native applications contain no direct modem/websocket/event-loop ownership.
- Inspect `packages/manifest.lua` package dependencies, destination paths and active aliases; no preview package may automatically replace the live preset.
- Review all changes touching SteamPlant outputs, reset behavior, scheduling and emergency-stop semantics.

## In-game test sequence

| Order | Component | Acceptance |
| --- | --- | --- |
| 1 | Package install | `pkgctl` installs preview packages and dependencies without changing live aliases |
| 2 | Hardware detection | `ioctl init`, `ioctl check`, `appctl check steamplant` do not activate outputs |
| 3 | Startup | SDK apps start and stop cleanly; terminal stays in text mode |
| 4 | Monitor | Text/graphics fallback, touch target mapping, pagination, resizing and redraw are correct |
| 5 | Discovery | Signed node appears online/stale; forged origin, altered payload and replay rejected |
| 6 | Snapshots | All DATA/GRAPHS and timestamps appear; stale/disconnected source is clearly marked |
| 7 | Storage read | `ping`, `namespaces`, `list`, `get` work only for allowlisted peers/namespaces |
| 8 | Storage failure | Missing media, missing key, oversized values, timeout and disabled writes are handled |
| 9 | Commands | Only signed target/app/control allowlist executes; no duplicate actuation from retries |
| 10 | Master | Compare HOME, machine selector, DATA, GRAPHS, CONTROLS, EVENTS, NETWORK and local maintenance |
| 11 | Pocket | Compare original navigation/controls, confirm dangerous actions and connection loss |
| 12 | Workstation | Compare console, devices, storage tree and administration behavior |
| 13 | WebBridge | Validate server schema, reconnect, heartbeat, source identity, role gate, ACK handling |
| 14 | SteamPlant | Test interlocks, sensor loss, startup/shutdown, abort and post-restart safe outputs using disconnected loads |
| 15 | Power loss | Restart during data write and command; confirm persistence and no duplicate actuation |

## Known pre-game gaps / blockers

- Master/Pocket/Workstation visual and behavioral parity remains partial; their SDK packages are previews, not substitutes.
- WebBridge and its Web backend have not completed native end-to-end migration.
- Snapshots lack SDK cryptographic source authentication; they are not safe authorization inputs.
- Event and command replay suppression is bounded and volatile across reboot.
- Storage replies are limited by signed ACK payload bounds; large historical data exports may need a paginated contract.
- No claim of game readiness is justified without verified GitHub CI and actual CC:Tweaked hardware tests.

## Reporting

Record commit SHA, Minecraft/CC:Tweaked/CC:Graphics versions, test computer IDs, network names, I/O mappings, monitor size, screenshots and logs. For each case mark PASS/FAIL/BLOCKED and capture a reproduction. Never paste SDK secrets.

## New snapshot gate

Before testing Master, Pocket, Workstation and WebBridge, provision each publisher with `client.origin=machine.key` and each receiver with an explicit `peers[publisherKey].snapshots=true` alongside a matching secret. Confirm valid snapshots appear; a missing signature, altered metric, different network, unknown machine and stale frame must be rejected. Do not interpret a connected modem as proof of authenticated data. The protocol intentionally rejects unsigned legacy snapshots.
