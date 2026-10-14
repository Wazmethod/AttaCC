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

## ORGANISATION V2

- `/etc/machine.lua` : identité logique (machine key, hostname, label, network).
- `/etc/apps.lua` : paramètres d’application et de modules, comme `motor.direction` ou `sensors.rpm.multiplier`.
- `/etc/io.lua` : périphériques physiques, redstone et `io.bindings`.
- `/etc/storage.lua` : destination et politique de synchronisation.
- `/etc/profile.lua` : couche historique conservée en lecture pour les installations existantes.

La priorité de chargement est : valeurs du preset, ancien profil, apps, puis IO. Les sauvegardes Storage V2 transportent les blocs apps, io et legacy. Le format V1 (profil simple) reste accepté lors d’une restauration.

## COMMANDES SUPPLÉMENTAIRES

```text
profilectl info
profilectl init
profilectl config
profilectl config inter
profilectl config remote <machine-key> [show|list|set|unset] [path] [value]
profilectl reset
```

`init` démarre directement l'assistant de première configuration : identité puis menus numérotés par catégorie et champ. `config inter` lance le même menu sans reconfigurer l'identité. `config` seul affiche l'aide de la sous-commande. `config remote` lit ou modifie l'enregistrement sauvegardé dans Storage ; il ne force pas le rechargement immédiat d'une application distante en cours d'exécution.

`info` affiche hostname, machine key, label, réseau, rôle, ID CraftOS et autres attributs utiles. `machines` présente l’hôte Storage, le namespace, le nombre d’identités sauvegardées et, lorsque disponible, hostname et réseau de chaque machine. Il ne s'agit pas de la liste des nœuds en ligne.

`reset` efface les configurations locales après saisie exacte de la machine key. Les sauvegardes distantes ne sont pas effacées ; penser à désactiver ou adapter la synchronisation avant le prochain bootstrap si l'objectif est de repartir de zéro.

## PRÉCAUTIONS DE MIGRATION

Conserver `machinectl` pendant une période de compatibilité. Tester `profilectl push`, `pull`, `show` et le chargement des trois fichiers sur une copie du monde avant toute suppression de l'ancien profil. La future édition Web distante n'est pas encore opérationnelle.

## CONFIGURATION V2 ET INTERFACES

`profilectl info` présente l'identité locale. `profilectl machines` affiche Storage host, namespace, le nombre de machines sauvegardées et leur hostname/réseau. `profilectl init` configure l'identité puis ouvre les menus numérotés de paramètres ; `profilectl config inter` ouvre seulement les paramètres.

```text
profilectl config remote <machine-key> list
profilectl config remote <machine-key> show motor.direction
profilectl config remote <machine-key> set motor.direction -1
profilectl config remote <machine-key> unset motor.direction
```

Fichiers : `/etc/machine.lua`, `/etc/apps.lua`, `/etc/io.lua`, `/etc/storage.lua` ; ancien `/etc/profile.lua` maintenu pendant la transition. La modification distante concerne l'enregistrement Storage et n'impose pas un reload instantané sur le CC cible. `profilectl reset` demande la machine key exacte pour confirmer la suppression des configurations locales (sans suppression distante).
