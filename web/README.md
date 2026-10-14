# AttaCC Web control plane

React/Vite frontend with a Node/WebSocket backend.

The Web UI is a generic AttaCC control plane. It consumes logical networks,
machine discovery, controllable application descriptors, module telemetry,
runtime state, topology and events.

## Production

```bash
cd web
cp .env.example .env
docker compose up -d --build
```

The container listens on port 8080. Preserve WebSocket upgrades for:

```text
/ws/machine
/ws/browser
```

## Master bridge

Create `/etc/webbridge.lua` on the Master:

```lua
return {
    url = "ws://192.168.1.202:8080/ws/machine",
    machineToken = "SAME_VALUE_AS_MACHINE_TOKEN",
    retrySeconds = 3,
}
```

Use `wss://` behind HTTPS.

The CC-side implementation is `apps/master/webbridge.lua`.

## Machine model

A discovered node reports:

- apps;
- modules;
- capabilities;
- runtime state;
- packages;
- processes;
- topology;
- telemetry.

The inspector reflects this model directly.

Controllable machine interfaces are derived from application telemetry
descriptors (`ui.app`, `ui.groups`, `ui.controls`). The Web UI therefore
does not need SteamPlant-specific transport logic.

## Administration

With `ADMIN_TOKEN`, the Web UI can request:

- package update;
- package configuration when exported by the package;
- node reboot;
- explicit machine/module commands.

No arbitrary remote shell is exposed.

## Development

Backend:

```bash
cd web/backend
npm install
npm start
```

Frontend:

```bash
cd web/frontend
npm install
npm run dev
```

Vite listens on port 5173 and proxies `/api` and `/ws` to port 8080.
