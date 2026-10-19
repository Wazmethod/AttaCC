# WebBridge SDK 1.1 — application autonome

Le WebBridge **n'est plus lancé par Master**. `app.webbridge` est une
application SDK native distincte, qui possède son transport modem,
sa boucle d'application et sa connexion WebSocket. Master, SteamPlant,
Pocket et les futures applications restent indépendants.

- ID SDK : `webbridge`
- Package : `app.webbridge` (dépend seulement de `core.runtime` et `module.network`)
- Programme : `apps/webbridge/main.lua`
- Relais : `lib/sdk_webbridge_relay.lua`
- Configuration WebSocket conservée : `/etc/webbridge.lua`
- Preset pour CC dédiée : `preset.webbridge`
- Mode : réception des snapshots, découvertes et événements SDK ;
  publication dans le protocole actuel du backend Web ;
  commandes web **désactivées** (`SDK READ ONLY`).

**La CC qui héberge WebBridge doit être sur le même réseau logique et avoir
un modem qui reçoit les snapshots et événements des machines surveillées.**
La présence d'un Master n'est plus requise ; un seul relais est recommandé
par réseau logique et endpoint web pour éviter les doublons d'événements.

## Installation à côté de Master ou d'une autre application

Sur la CC hôte, avec le dépôt HTTP déjà synchronisé :

```text
pkgctl source test
pkgctl install app.webbridge
pkgctl update core.runtime
pkgctl update app.master    # uniquement si cette CC utilise Master
webbridgectl status
webbridgectl configure     # uniquement si /etc/webbridge.lua manque ou est erroné
webbridgectl enable
reboot
```

`enable` inscrit `webbridge=true` dans `/etc/attacc/services.lua`.
Le startup SDK lance un **onglet indépendant** `appctl.lua webbridge`
au prochain démarrage, puis démarre normalement l'application du preset.
Il n'est pas nécessaire d'activer un autre preset ni de faire porter le
WebSocket à Master. Désactiver par `webbridgectl disable`, puis reboot.
La commande `pkgctl run webbridge` lance aussi l'application, mais
dans le terminal courant : elle n'active pas l'autostart.

Si l'on migre depuis l'ancien Master qui embarquait `webbridgectl`,
installer **app.webbridge avant d'actualiser app.master** permet de garder
cet outil partagé pendant la migration. `pkgctl` retire les anciens
fichiers devenus obsolètes de Master.

## Installation sur une CC dédiée, sans Master

```text
pkgctl install preset.webbridge
systemctl init
systemctl status
webbridgectl configure
pkgctl activate preset.webbridge
reboot
```

Dans `systemctl init`, utiliser une clé de machine unique et le **même
réseau logique** que les CC à superviser, par exemple `infra-main`.
La CC hôte doit pouvoir accéder au WebSocket `/ws/machine`.
On conserve les valeurs de `/etc/webbridge.lua` après migration :
l'URL et le token sont les mêmes, sans exposition du token dans les
journaux ni dans `webbridgectl status`.

Aucun `webbridgectl enable` n'est nécessaire avec le preset dédié :
le preset démarre directement l'application WebBridge.

## Vérifications en jeu

1. Sur la CC relais : `webbridgectl status` et `systemctl status`.
   Si la commande affiche « not started » malgré le bridge connecté,
   consulter l'onglet `webbridge` : les états locaux persistés par
   plusieurs applications peuvent être partagés.
2. Sur le site : `WEB CONNECTED`, `BRIDGE LINKED`, `SDK READ ONLY`.
3. Dans OPERATIONS : SteamPlant et les autres CC du réseau doivent se
   mettre à jour normalement, même lorsque Master est arrêté.
4. Sur une CC hébergeant plusieurs applications : Master et WebBridge
   doivent avoir **deux onglets** distincts, et les graphiques ne doivent
   pas être remplacés par la page d'état WebBridge.
5. Après reboot du relais, vérifier la reconnexion automatique et le
   retour des nœuds en ligne.
6. Déconnecter temporairement Master si nécessaire pour confirmer
   que WebBridge n'en dépend plus.

Le relais est `display=false` et `publishLocal=false` : il n'écrit pas
le même cache d'affichage JSON qu'une application colocataire. Son
inventaire réseau et son descripteur de télémétrie restent publiés via le SDK.

## À ne pas confondre

`app.webbridge_preview` et `apps/master/sdk_webbridge.lua` sont
d'anciennes variantes expérimentales. Pour le site existant, utiliser
**`app.webbridge`**, qui adapte le transport SDK au protocole reconnu
par le backend.
