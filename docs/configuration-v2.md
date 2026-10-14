# Configuration V2 — migration et validation

Branche : `refactor/native-runtime-v1` (travail non fusionné).

## Organisation

| Fichier | Responsabilité | Exemples |
|---|---|---|
| `/etc/machine.lua` | Identité logique | key, hostname, label, network |
| `/etc/apps.lua` | Application et modules | motor.direction, sensors.rpm.multiplier, display |
| `/etc/io.lua` | Connexions physiques | peripherals.motor, redstone.mainClutch, io.bindings |
| `/etc/storage.lua` | Destination des sauvegardes | targetMachine, namespace, enabled, timeout |
| `/etc/profile.lua` | **Compatibilité héritée** | anciens réglages, chargés avant apps/io |

Ordre de priorité au démarrage : defaults du preset < ancien profil < apps < io. Les nouveaux réglages locaux sont enregistrés dans apps/io. Les sauvegardes utilisent un objet `attacc.config.v2` contenant `apps`, `io` et `legacy`. Une sauvegarde au format historique reste lisible en restauration.

## Commandes

```text
profilectl info
profilectl machines
profilectl init
profilectl config
profilectl config inter
profilectl config list
profilectl config show motor.direction
profilectl config set motor.direction -1
profilectl config unset motor.direction
profilectl config remote <machine-key> list
profilectl config remote <machine-key> show motor.direction
profilectl config remote <machine-key> set motor.direction -1
profilectl config remote <machine-key> unset motor.direction
profilectl show
profilectl push
profilectl pull
profilectl reset
```

Le menu `init` commence par les identifiants machine et continue avec des menus numérotés par catégorie et paramètres. `config inter` ouvre le menu sans toucher à l'identité. Les opérations `remote` éditent une **sauvegarde Storage**, pas immédiatement l'état mémoire d'un processus distant. Le rechargement applicatif doit être contrôlé séparément.

`profilectl machines` affiche l'hôte Storage configuré, le namespace, le nombre de configurations de machines enregistrées, le hostname et le réseau lorsqu'ils sont présents dans l'identité sauvegardée.

`profilectl reset` demande la machine key exacte avant suppression des fichiers locaux d'identité, apps, IO et legacy ; le Storage distant est conservé. Si la synchronisation reste activée, la prochaine récupération peut réinjecter les anciennes données.

## Vérifications obligatoires avant migration

1. Sauvegarder les contenus actuels de `/etc/machine.lua`, `/etc/profile.lua`, `/etc/storage.lua` et le Store.
2. Sur **une copie du monde**, mettre à jour uniquement une SteamPlant de test.
3. Vérifier `profilectl info`, `show`, `config list`, `config inter` et le menu `init`.
4. Définir `motor.direction` sur une valeur de test puis vérifier la surcharge dans `/etc/apps.lua`.
5. Définir `peripherals.motor` et un paramètre redstone, vérifier `/etc/io.lua`.
6. Redémarrer le programme et confirmer que les valeurs effectives correspondent aux fichiers.
7. Faire `profilectl push`, lire `machines`, puis `pull` sur la même machine de test et comparer fichiers/sorties.
8. Tester `config remote show`, `set`, puis `pull`. Confirmer qu'aucune autre clé machine n'a été modifiée.
9. Vérifier qu'un profil V1 ancien est encore restaurable sans effacement de données.
10. Tester `reset` uniquement sur une identité de test, en vérifiant qu'une saisie incorrecte annule.

## Travaux non finalisés

- Édition graphique WebUI des configurations distantes : exige un canal de requêtes ciblées et authentifiées, validation, sauvegarde, accusé de réception et état d'erreur.
- Assistant de création de nouveaux bindings I/O (`io.bindings`) : les paramètres matériels existants sont éditables ; la définition graphique d'une nouvelle liaison reste à développer.
- Suppression effective de l'ancien `machinectl` : différée pour préserver les scripts installés.
- Tests de syntaxe/chargement Lua et recette en jeu : non réalisés ici.

Aucun merge vers `dev` tant que ces validations ne sont pas terminées.
