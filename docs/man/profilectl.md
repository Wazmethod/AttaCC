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
profilectl config list
profilectl config show <section.path>
profilectl config set <section.path> <value>
profilectl config unset <section.path>
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

## MODIFICATION CIBLÉE
`profilectl config list` montre les feuilles configurables et les valeurs possibles ou types ; `show` affiche la valeur effective et l’éventuelle surcharge locale. `set` ne modifie qu’une seule valeur de `/etc/profile.lua` ; `unset` supprime sa surcharge pour retrouver le défaut au redémarrage.

```lua
profilectl config show motor.direction
profilectl config set motor.direction -1
profilectl config set sensors.rpm.multiplier 1
profilectl config unset motor.direction
```

`profilectl init` demande désormais une section ou `all`, puis les champs imbriqués, avec choix admis (`-1/1` pour la direction moteur et le multiplicateur RPM, `auto/text/ccgraphics` pour le rendu, etc.). Le fichier par défaut est chargé en premier et `/etc/profile.lua` a priorité pour les propriétés qu’il définit. Les champs complexes non typés doivent encore être édités par `profilectl edit`.
