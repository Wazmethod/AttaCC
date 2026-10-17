# AttaCC Web control plane — SDK 1.1

The web frontend now uses the same **graphite / cyan / grey / yellow / red**
visual language as the in-game AttaCC monitor UI. The layout and existing
documentation/repository pages are retained.

## Deployment (web server)

The browser frontend and Node backend need to be rebuilt to pick up the
WebBridge protocol capability flag and the new theme:

```sh
cd web
# Keep your existing .env secrets and data volume.
docker compose up -d --build
docker compose logs --tail=80 steamplant-web
```

The container listens on port 8080. Proxies must preserve WebSocket upgrades:

- `/ws/machine` — Minecraft Master -> backend
- `/ws/browser` — browser -> backend

A browser may show `WEB CONNECTED` while `BRIDGE OFFLINE` if Master is not
connected. `GET /api/status` returns `bridgeConnected`, `bridgeCount`,
`commandsEnabled`, nodes and telemetry to distinguish these states.

## Minecraft Master — SDK-native bridge

The **SDK Master** contains the WebBridge directly. No separate legacy
`apps/master/webbridge.lua` tab or daemon is necessary.

On Master, first update the source/revision then:

```text
pkgctl source test
pkgctl update app.master
webbridgectl configure
reboot
```

`webbridgectl configure` writes the existing `/etc/webbridge.lua` format:

```lua
return {
    url = "ws://192.168.1.202:8080/ws/machine",
    machineToken = "MATCH_BACKEND_MACHINE_TOKEN",
    retrySeconds = 3
}
```

Preserve your existing URL and token when reconfiguring; do **not** replace
secrets with examples. Use `wss://` when the site is behind HTTPS. The Master
and backend must point to the same site and use identical machine tokens.

On the Master interface check the `WebBridge` status. On the website, check
`BRIDGE LINKED`, `WEB CONNECTED` and live machine/graph data.

**Protocol:** The SDK Master relays native SDK snapshots as the backend's
existing `telemetry` shape, native discovery as `node_status`, and
`app.event` messages as `event`. Its own application is also published.
This works with the current Node browser API and does not require restoring
a second, legacy ComputerCraft runtime.

**Commands:** Web SDK mode is intentionally **read-only for now**. The website
shows `SDK READ ONLY` and disables control, reboot, update and configuration
buttons rather than claiming an old-protocol action was accepted. Repository
administration (performed on the web server itself) remains available using
its existing admin token. A compatible SDK command bridge can be implemented
and tested separately later; do not bypass SDK authorization.

## Troubleshooting

If the website still shows `BRIDGE OFFLINE`:

1. Check the Master has been updated and rebooted after configuration.
2. Check `/etc/webbridge.lua` has the right URL, token and `/ws/machine` path.
3. Check the web container logs for startup errors and the proxy's WebSocket
   upgrade configuration; verify that the site itself reports `WEB CONNECTED`.
4. If the bridge connects but telemetry stays empty, check Master is receiving
   fresh SDK snapshots in its MACHINE/DATA views and the server's
   `/api/status` JSON reports populated `nodes` and `telemetry`.

## Development

Backend:

```sh
cd web/backend
npm install
npm start
```

Frontend:

```sh
cd web/frontend
npm install
npm run dev
```

Vite listens on port 5173 and proxies `/api` and `/ws` to port 8080.
