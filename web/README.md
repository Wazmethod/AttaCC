# CC Infrastructure Web Dashboard

React + Vite frontend with a Node/WebSocket backend.

The dashboard is now an infrastructure control plane: named logical networks,
machine discovery, module telemetry, identity conflicts and the global event bus
are represented independently from any one automation module. The UI keeps the
Minecraft-inspired industrial visual language without shipping Minecraft assets.

## Production deployment

From the repository root:

```bash
git checkout dev
git pull
cd web
cp .env.example .env
nano .env
docker compose up -d --build
```

The multi-stage Docker build:

1. installs the Vite/React frontend dependencies;
2. runs `npm run build`;
3. copies the generated `dist/` into the Node backend image;
4. starts one container on port 8080.

Open:

```text
http://SERVER_IP:8080
```

Behind Traefik/Nginx, proxy the same port and preserve WebSocket upgrades for:

```text
/ws/machine
/ws/browser
```

## Updating

```bash
git pull
cd web
docker compose up -d --build
```

Docker rebuilds the Vite app automatically. You do not need Node/npm installed on the host if Docker is available.

## Development mode

Run backend:

```bash
cd web/backend
npm install
npm start
```

Run frontend in another shell:

```bash
cd web/frontend
npm install
npm run dev
```

Vite listens on port 5173 and proxies `/api` and `/ws` to the backend on port 8080.

## Master bridge

Create `web.local.lua` on the Master:

```lua
return {
    url = "ws://192.168.1.202:8080/ws/machine",
    machineToken = "SAME_VALUE_AS_MACHINE_TOKEN",
    retrySeconds = 3,
}
```

For HTTPS use `wss://...`.

The browser uses `/ws/browser` for live telemetry. Commands still go through the authenticated REST endpoint `POST /api/command`.

## Secrets

- `MACHINE_TOKEN`: authenticates the CC Master WebSocket.
- `ADMIN_TOKEN`: authorizes browser control commands.

Never commit `.env` or `web.local.lua`.


## Infrastructure topology and runtime services

The Web control plane now receives:

- named logical networks;
- machines and logical identities;
- advertised modules;
- module telemetry;
- runtime service states from `systemctl`;
- declarative topology links;
- the global module/system event bus.

The **TOPOLOGY** view renders relationships declared in each machine's
`/etc/profile.lua`. Machine details also expose the runtime services reported
by that node.


## Multiple sites

The backend accepts multiple simultaneous CC Web bridges. Each bridge learns
the logical networks visible at its site, and commands/reboots are routed by
network. If a network has not been learned yet, the command is broadcast to
connected bridges; the CC network layer still rejects foreign-network traffic.

This allows one central Web control plane to aggregate separate installations
while keeping their machine identities and logical networks distinct.


## System graph and service capabilities

Each discovered node may export a system inventory containing:

- `*.service` units and their runtime state;
- the binary/process which owns each service;
- modules consumed/provided by that service;
- installed package/version information;
- optional Web capability metadata;
- structured service data and explicitly exported service commands.

The machine inspector renders the generic relationship:

```text
service -> binary/process -> module(s)
```

With `ADMIN_TOKEN`, the Web UI may request service start/stop/restart, execute commands explicitly declared by a service unit, request package updates, and reboot a node. Arbitrary remote shell execution is not exposed through the Web API.

Service units opt into custom Web UI/data with a `web` descriptor. Runtime code publishes structured values through `lib.webcap`.

## Updating CC nodes from the Web UI

The UPDATE action sends a `pkgctl update` request to the selected CC node. The package manager resolves its explicit roots and dependencies on that node. Configuration is preserved and migrations converge recognized historical layouts directly to the current filesystem schema.
