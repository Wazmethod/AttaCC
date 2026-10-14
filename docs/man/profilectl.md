# profilectl(1) — Profil et synchronisation

## NOM
**profilectl** — inspecter, éditer et synchroniser les profils des machines AttaCC.

## SYNOPSIS
```text
profilectl
profilectl status
profilectl show
profilectl init
profilectl edit
profilectl reset
profilectl storage-sync
profilectl push
profilectl pull
profilectl sync
profilectl machines
profilectl edit remote <machine-key> [profile|machine]
```

## DESCRIPTION
`show` affiche la configuration effective et `/etc/machine.lua`, `/etc/profile.lua`, `/etc/storage.lua` sans ouvrir l’éditeur. `init` propose un assistant interactif : sections applicatives et paramètres simples de modules ; `edit` ouvre l’éditeur du profil spécifique au preset. `push` envoie la configuration locale vers Storage, `pull` (alias `sync`) récupère la copie distante ; **la récupération peut remplacer des valeurs locales**. `machines` liste les identités synchronisées, `edit remote` édite une configuration distante.

`storage-sync` active la synchronisation et règle son délai ; la destination et le namespace sont sélectionnés par `storagectl init/use`. Les assistants `init` locaux diffèrent entre presets ; des paramètres complexes peuvent nécessiter `edit`.

## EXEMPLES
```lua
storagectl init
profilectl init
profilectl show
profilectl storage-sync
profilectl push
profilectl machines
profilectl pull
```

## DÉBOGAGE
En cas de timeout : `storagectl target`, `storagectl ping`, contrôler la clé machine. Sauvegarder les fichiers `/etc` avant le premier pull ou un reset.

## VOIR AUSSI
[storagectl](storagectl.md), [machinectl](machinectl.md).
