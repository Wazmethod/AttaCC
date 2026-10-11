# Steam Plant Web POC

POC Docker très simple pour relier le Master CC:Tweaked à une interface web distante.

## Déploiement

```bash
cp .env.example .env
nano .env
docker compose up -d --build
```

Puis ouvrir :

```text
http://IP_DU_SERVEUR:8080
```

Derrière Traefik/Nginx, publier simplement le service sur le port 8080. Le WebSocket est sur `/ws/machine`.

## Côté CC:Tweaked

Copier `cc/webbridge.lua` sur le Master et modifier :

```lua
local WS_URL = "ws://IP_DU_SERVEUR:8080/ws/machine"
local MACHINE_TOKEN = "..."
```

Avec HTTPS :

```lua
local WS_URL = "wss://steam.example.com/ws/machine"
```

Le domaine/IP doit être autorisé dans la configuration HTTP de CC:Tweaked.

Lancer ensuite :

```text
webbridge
```

Le bridge écoute la télémétrie locale du Collector et l'envoie au serveur.
Les commandes web sont retransmises vers le Collector via le canal CC 4245.

## API

- `GET /api/status`
- `GET /api/events`
- `GET /api/health`
- `POST /api/command` avec `Authorization: Bearer ADMIN_TOKEN`

Commandes compatibles :
`procedure`, `abort`, `arm`, `disarm`, `main_on`, `main_off`,
`gen_on`, `gen_off`, `alt_on`, `alt_off`, `motor_stop`,
`motor_speed`, `running_topology`, `all_cut`.

## Persistance

Les événements sont stockés dans :

```text
./data/events.jsonl
```

La télémétrie instantanée reste en mémoire dans ce POC.

## Sécurité

Le POC utilise :
- `MACHINE_TOKEN` pour le WebSocket CC
- `ADMIN_TOKEN` pour les commandes web

Pour une version production : HTTPS/WSS obligatoire, vraie authentification utilisateur,
permissions, rate limiting et base de données pour l'historique.
