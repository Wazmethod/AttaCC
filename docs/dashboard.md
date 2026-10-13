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
`/etc/webbridge.lua` exists.

Create `/etc/webbridge.lua` on the Master:

```lua
return {
    url = "wss://steam.example.com/ws/machine",
    machineToken = "SAME_VALUE_AS_MACHINE_TOKEN",
    retrySeconds = 3,
}
```

Then reboot the Master. The generic init/service runtime discovers
`webbridge.service` from its unit definition and starts `webbridge.lua`
when the required configuration file is present.

## 3. Browser control

The first command from the browser asks for `ADMIN_TOKEN`.
This token is stored in the browser local storage.

Do not commit `/etc/webbridge.lua`, `.env`, or tokens.


## Service inventory and administration

The machine inspector receives each node's generic system snapshot:

```text
service -> binary/process -> modules
```

Web-capable services may export structured data and explicitly allow custom
commands. Administrators can start/stop/restart services, request full or
per-package updates, and reboot nodes. Recent service journal entries are shown
with each service. Arbitrary shell execution is deliberately not exposed.
