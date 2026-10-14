# pkgctl(1) — Gestionnaire de paquets AttaCC

## NOM
**pkgctl** — installer et mettre à jour les presets, applications, modules et dépendances.

## SYNOPSIS
```text
pkgctl
pkgctl list
pkgctl status
pkgctl show <package>
pkgctl deps <package>
pkgctl install <package>
pkgctl configure <package>
pkgctl update [package]
pkgctl upgrade [package]
pkgctl prune
```

## DESCRIPTION
`list` énumère les paquets du manifeste. `status` contrôle les installations et fichiers absents. `show/deps` détaille un paquet et sa fermeture de dépendances. `install` installe les fichiers et dépendances. `configure` exécute le configurateur quand disponible. `update/upgrade` rafraîchit les paquets ; `prune` supprime les paquets non requis par les racines explicitement installées.

## EXEMPLES
```lua
pkgctl status
pkgctl show preset.master
pkgctl install module.storage-client
pkgctl update
reboot
```

## ATTENTION
Les presets ont parfois des destinations communes comme `lib/config.lua`, `lib/ui.lua` et `profilectl.lua` ; ne pas mélanger des presets incompatibles sur le même ordinateur. Vérifier `status` avant et après `prune`.

## VOIR AUSSI
[guide d’exploitation](../guide-exploitation.md), [installation](../installation.md).
