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

## OPERATIONS — interface SDK unifiée

La page `OPERATIONS` affiche une seule application SDK à la fois :

- sélecteur d'applications dans le panneau latéral (nom, machine, réseau, état et nombre de mesures/graphes/contrôles) ;
- onglets `DATA`, `GRAPHS`, `CONTROLS`, `EVENTS` et `MACHINE` dans l'espace principal ;
- axes Y numériques et axe X temporel (secondes écoulées) utilisant `min`, `max` et `timeWindow` des graphes SDK ;
- mesures regroupées par catégorie, booléens affichés avec leurs libellés SDK ;
- événements filtrés par application/machine avec colonnes TIME / SOURCE / INFORMATION / CODE ;
- onglet MACHINE intégré et accessible depuis NETWORK, sans modal ;
- graphique SVG ajusté à toute la largeur disponible, même pour une rangée entière ;
- mesures dans une grille compacte, graphes occupant la largeur disponible et contrôles regroupés ;
- recherche et navigation adaptées aux écrans étroits : la liste passe au-dessus du panneau sur mobile.

Le WebBridge SDK reste en **lecture seule** et les actions restent désactivées tant qu'un transport de commandes autorisé n'a pas été validé. Les autres pages web, la documentation et le dépôt ne changent pas.

La restauration WebBridge (`BRIDGE LINKED`) et l'arrivée de télémétrie ont été confirmées en jeu. Les nouveaux onglets, axes et regroupements doivent encore être vérifiés dans le navigateur après reconstruction du conteneur.

Le SDK publie automatiquement un inventaire compact de chaque CC exécutant une application : versions des packages, nombre total de packages, applications actives, modules, onglets/processus CraftOS ouverts, disque et quelques logs. Il est rafraîchi toutes les 15 secondes et conservé entre les annonces légères de présence. Les noms simples `apps`/`modules` restent compatibles avec NETWORK ; les détails enrichis sont dans `node.system`. Un clic sur une machine depuis NETWORK ouvre directement l’onglet MACHINE d’OPERATIONS, même en l’absence de télémétrie de l’application. Pour recevoir ces nouvelles informations, mettre à jour `core.runtime` sur chaque CC, ainsi que `app.master` sur Master, puis redémarrer les applications.

## Independent SDK WebBridge

WebBridge now runs as **`app.webbridge`**, an SDK-native application which
can live on **any CC with a wireless modem**, including a dedicated machine
with **no Master on the logical network**. Master no longer owns the WebSocket.

Keep your existing `/etc/webbridge.lua`, which contains the server URL
and `machineToken`; the token must match the backend `MACHINE_TOKEN`.
Nothing changes on the website and **no WebUI rebuild is required solely
for this decoupling**.

### Running beside Master, Pocket or SteamPlant

```text
pkgctl install app.webbridge
pkgctl update core.runtime
pkgctl update app.master   # Master CC only
webbridgectl status
webbridgectl configure    # only if configuration is missing
webbridgectl enable
reboot
```

The startup SDK launches a second multishell tab for WebBridge.
`webbridgectl disable` disables this additional autostart after reboot.
For a dedicated CC, install and activate `preset.webbridge` instead.
See [WebBridge SDK deployment](../docs/operations/webbridge-sdk.md).

### Dedicated WebBridge CC without Master

```text
pkgctl install preset.webbridge
systemctl init
webbridgectl configure
pkgctl activate preset.webbridge
reboot
```

Configure a unique machine key and the logical network of the apps to watch
during `systemctl init`. The relay forwards snapshots, machine discovery
and `app.event` messages using the backend's established WebSocket format.

**Commands:** `app.webbridge` is **read-only**; it never sends unsigned
remote administration commands. Repository administration on the server
remains a separate feature. Prefer one relay per logical network/backend
endpoint to avoid duplicate forwarded events.

## Troubleshooting

If `BRIDGE OFFLINE` returns, check **the CC running WebBridge**, not
necessarily Master:

1. `webbridgectl status` and the separate `webbridge` multishell tab.
2. Correct `/etc/webbridge.lua` URL (ending in `/ws/machine`) and token.
3. `systemctl status` and the modem / logical network configuration.
4. Container logs and the WebSocket upgrade rules in the web proxy.
5. `/api/status` should show `bridgeConnected=true` and live nodes/telemetry.

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
