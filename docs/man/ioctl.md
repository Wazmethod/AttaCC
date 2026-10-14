# ioctl(1) — Entrées/sorties logiques

## NOM
**ioctl** — examiner et manipuler les bindings I/O enregistrés par AttaCC.

## SYNOPSIS
```text
ioctl
ioctl list
ioctl show <name>
ioctl read <name>
ioctl write <name> <value>
```

## DESCRIPTION
`list` affiche les périphériques logiques. `show` détaille un binding, `read` lit sa valeur, `write` tente d’écrire une valeur vers le canal ou périphérique associé.

## PRÉCAUTIONS
`write` peut avoir un effet physique/redstone : ne l’utiliser que sur un périphérique de test ou lors d’une procédure autorisée. Le nom de binding provient de la configuration propre au module.

## VOIR AUSSI
[guide d’exploitation](../guide-exploitation.md), [modules](../module-development.md).

## PARTICULARITÉ STEAMPLANT
Le registre `config.io.bindings` est vide par défaut dans le preset SteamPlant. `ioctl list` peut donc n’afficher aucune entrée même si le moteur et les capteurs fonctionnent : ceux-ci passent par `config.peripherals` et le module SteamPlant. Pour modifier le sens du moteur, le multiplicateur RPM ou un nom de périphérique, utiliser `profilectl config`. `ioctl` reste dédié aux bindings I/O explicites et à leurs opérations matérielles.

## ASSISTANT MATERIEL

```lua
ioctl hardware
ioctl bind
ioctl list
```

`hardware` affiche les peripheriques connectes avec leur nom exact et leur type. `bind` cree une liaison logique input/output de type peripheral ou redstone, propose le materiel disponible puis controle le nom de methode. La configuration est enregistree dans `/etc/io.lua` sous `io.bindings`. Redemarrer l'application avant `ioctl list` car la configuration du preset est chargee au lancement. Les commandes `ioctl write` gardent une confirmation pour les sorties physiques.
