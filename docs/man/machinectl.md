# machinectl(1) — Identité logique d’une machine

## NOM
**machinectl** — inspection, initialisation et migration de l’identité d’un ordinateur AttaCC.

## SYNOPSIS
```text
machinectl
machinectl status
machinectl init
machinectl hostname [new-hostname]
machinectl export [file]
machinectl import [migration-code]
machinectl reset
```

## DESCRIPTION
`status` donne clé machine, hostname, label, rôle, apps/modules, réseau et identité physique. `init` invite à renseigner **Machine Key**, **Hostname**, **Label**, **Network**. `hostname` affiche ou modifie le nom. `export` génère un code `IM1-` dans un fichier (par défaut `machine-migration.txt`) ; `import` lit le code fourni, ou le demande interactuellement ; `reset` supprime le fichier local après confirmation.

## IMPORTANT
Une clé machine doit être unique par nœud logique ; l’import sur un second CC sans retirer l’ancien peut créer des doublons sur le réseau. Les changements d’identité ou de réseau peuvent nécessiter un reboot.

## FICHIERS
`/etc/machine.lua`.

## VOIR AUSSI
[profilectl](profilectl.md), [audit technique](../audit-technique.md).
