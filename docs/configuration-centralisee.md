# Configuration centralisée, complétion et identité AttaCC

Branche de travail : `refactor/native-runtime-v1`. Ne pas merger sans tests.

## Contrat matériel

Une application déclare `config.io.requirements` (rôle logique, type physique, required, description). `ioctl init` associe les rôles au matériel via `/etc/io.lua`, `ioctl check` les vérifie et le registre `lib.io_registry` les expose à l'application. `ioctl bind` reste réservé à des bindings personnalisés, dont le nom logique est un alias libre ; pour SteamPlant, utiliser `ioctl init`.

## Centralisation des configurations

`profilectl config consolidate` copie la configuration **effective** des applications et modules dans `/etc/apps.lua` et les informations périphériques/redstone dans `/etc/io.lua`. La machine conserve son identité dans `/etc/machine.lua`, ses réglages généraux durables dans `/etc/profile.lua`, et la destination du Storage dans `/etc/storage.lua`. L'opération nécessite de saisir `CONSOLIDATE`. `profilectl push` conserve les configurations centralisées en Storage. La copie complète des valeurs par défaut les fige : examiner les évolutions des presets lors des futures mises à jour.

Commandes :
```lua
profilectl config consolidate
profilectl show
profilectl push
profilectl pull
```

## Autocomplétion

```lua
profilectl shell show
profilectl shell completion on
profilectl shell completion off
profilectl shell mode standard
profilectl shell mode attacc
```

L'autocomplétion des sous-commandes AttaCC s'enregistre au boot dans le Shell CraftOS. **Le mode attacc n'efface pas les commandes ni fichiers CraftOS** : la restriction du Shell système doit être développée et testée à part, car supprimer l'accès à `edit`, `reboot` ou `pkgctl` rendrait le dépannage risqué.

## Changement contrôlé de Machine Key (conception — NON implémenté)

Le hostname et label restent éditables par chaque machine. Le changement de **Machine Key** devra être orchestré depuis le Master, après confirmation de l'ancienne et nouvelle clé :

1. Vérifier droits administrateur, unicité de la nouvelle clé, présence de la machine et disponibilité du Storage.
2. Créer une sauvegarde des enregistrements `machine:<old>` et `profile:<old>` et un journal d'audit.
3. Préparer les nouveaux enregistrements sous la nouvelle clé **sans supprimer les anciens**.
4. Obtenir un ACK explicite de la machine cible, mettre à jour `/etc/machine.lua` de façon atomique et vérifier son redémarrage/annonce avec la nouvelle clé.
5. Confirmer le nouvel accès `profilectl push/pull`, puis archiver l'ancien mapping après vérification et délai.
6. En cas d'échec, restaurer l'ancienne identité et les références Storage.

Le transport radio de contrôle actuel n'a pas d'authentification forte ; ne pas ajouter de requête radio arbitraire « change key » sans contrôle d'autorisation. Le Master doit détenir l'autorité administrative et journaliser chaque changement.

## Interface Web

Les grilles du dashboard conservent 2 colonnes à partir de 900 px et 3 à partir de 1380 px lorsque l'espace disponible le permet. Les cartes de contrôle et métriques gardent plusieurs colonnes sur tablette. Cela ne remplace pas la future interface d'édition distante des profils, qui nécessite un backend authentifié et un accusé de réception.

## Validation

- `profilectl shell completion on` puis reboot ; vérifier la complétion par Tab de `profilectl config` et `storagectl`.
- Tester `profilectl config consolidate` sur machine de **test**, inspecter `/etc/apps.lua` et `/etc/io.lua`, puis push/pull et reboot.
- Tester `ioctl init` et `ioctl check` en gardant la contraption sécurisée.
- Rebuild Web et contrôler les layouts aux largeurs 750, 1100 et 1500 px.
- Ne pas effectuer de migration Machine Key tant que le protocole et le rollback ne sont pas implémentés et testés.
