# Hosted dashboard

The hosted dashboard lives in `web/`.

## 1. Deploy the web service

```bash
git clone https://github.com/Wazmethod/steamplant-cc.git
cd steamplant-cc/web
cp .env.example .env
nano .env
docker compose up -d --build
```

Choose two different random values:

```env
MACHINE_TOKEN=...
ADMIN_TOKEN=...
```

Open:

```text
http://SERVER_IP:8080
```

For production, put the service behind HTTPS and use a `wss://` URL.

## 2. Enable the bridge on the Master

The Master installer deploys `webbridge.lua`, but it stays disabled until
`web.local.lua` exists.

Create `web.local.lua` on the Master:

```lua
return {
    url = "wss://steam.example.com/ws/machine",
    machineToken = "SAME_VALUE_AS_MACHINE_TOKEN",
    retrySeconds = 3,
}
```

Then reboot the Master.

The startup script launches the wall dashboard and WebSocket bridge together.

## 3. Browser control

The first command from the browser asks for `ADMIN_TOKEN`.
This token is stored in the browser local storage.

Do not commit `web.local.lua`, `.env`, or tokens.
