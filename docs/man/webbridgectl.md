# webbridgectl(1) — Configuration WebBridge

## NOM
**webbridgectl** — personnaliser les étiquettes des réseaux présentés au Web.

## SYNOPSIS
```text
webbridgectl
webbridgectl configure
```

## DESCRIPTION
Sur le Master/WebBridge, sans argument la commande affiche son aide. `configure` ouvre l’assistant des labels, lit les réseaux observés et sauvegarde les noms. Depuis l’onglet WebBridge, le bouton « Network Labels » doit ouvrir cette commande avec son argument `configure`.

## FICHIERS
`/etc/webbridge.lua` pour les labels ; `/run/attacc/webbridge-networks.json` pour les réseaux observés.

## DÉBOGAGE
Si les changements n’apparaissent pas : vérifier le fichier, l’onglet WebBridge, puis la liaison WebSocket vers le serveur.

## VOIR AUSSI
[guide d’exploitation](../guide-exploitation.md), [validation infrastructure](../validation-infrastructure.md).
