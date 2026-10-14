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
