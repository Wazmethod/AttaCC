# webbridgectl(1) — WebBridge SDK indépendant

## NOM

**webbridgectl** — inspecter et configurer la connexion WebSocket du
service SDK WebBridge, et activer ou désactiver son autostart en parallèle.

## SYNOPSIS

```text
webbridgectl
webbridgectl status
webbridgectl configure
webbridgectl enable
webbridgectl disable
```

## DESCRIPTION

Livré par `app.webbridge`, indépendamment de `app.master`.

- `status` : autostart, URL, token configuré/absent et dernier état de connexion connu (jamais la valeur du token).
- `configure` : assistant pour `/etc/webbridge.lua` (WebSocket, secret machine, délai de reconnexion et labels réseau).
- `enable` : lancement **optionnel dans un autre onglet au prochain reboot** par le startup SDK, quel que soit le preset courant.
- `disable` : désactivation de cet autostart au prochain reboot.

Pour une CC dédiée, installer et activer `preset.webbridge` ;
`enable` n'est pas nécessaire : le preset lance directement WebBridge.

## FICHIERS

- `/etc/webbridge.lua` : URL/secret/labels persistants.
- `/etc/attacc/services.lua` : `webbridge=true` pour l'autostart optionnel.
- `/run/attacc/webbridge-networks.json` : liste d'étiquettes observées si disponible.

## REMARQUES

La CC WebBridge n'a pas besoin de Master mais doit avoir accès au réseau
logique des applications surveillées et au serveur web. La supervision
est en lecture seule ; les commandes distantes signées font l'objet
d'une évolution distincte.

## VOIR AUSSI

[WebBridge autonome](../operations/webbridge-sdk.md), [guide d’exploitation](../guide-exploitation.md).
