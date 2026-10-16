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
- **Storage:** shared storage protocol must be reworked into SDK services.
- **SDK network events/discovery:** transport and subscriptions implemented;
  source authentication still absent. Treat discovery as untrusted.

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
