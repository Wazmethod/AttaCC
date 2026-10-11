# Steam Plant Web Dashboard

React + Vite frontend with a Node/WebSocket backend.

The dashboard uses a Minecraft-inspired industrial visual language without shipping Minecraft assets.

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
