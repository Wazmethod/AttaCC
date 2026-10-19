# AttaCC SDK 1.1 — stockage : état réel et trajectoire

Cette revue distingue le **stockage actuel**, réellement présent dans le dépôt,
d'un **NAS de fichiers** éventuel. Aucun serveur de fichiers n'est créé ici.
L'interface web reste hors périmètre pour cette passe.

## 1. Ce qui existe aujourd'hui

| Composant | Utilité | Statut |
| --- | --- | --- |
| `modules/storage/backend.lua` | Clé/valeur JSON persistante par namespace ; backend local ou disque CC monté | Implémenté |
| `module.storage-server` + `storagehost.lua` | Hôte historique sur canaux 4255/4256 et CLI `storagehostctl` | Hérité du transport précédent |
| `module.storage-client` + `storagectl` | Client historique configuré sur une clé machine | Implémenté, protocole historique |
| `core/sdk_storage.lua` | Contrôle `storage_request` via canal de commandes SDK et autorisation du pair | Implémenté, distinct du protocole précédent |
| `app.storage_agent` | Application SDK autonome hébergeant ce contrôle | Disponible, service **désactivé par défaut** |
| `preset.storage` | Démarrage automatique de `storage_agent` sur une CC dédiée | Préparé, **n'active pas** les écritures |
| `du` / `df` | Inspecter l'occupation du répertoire courant et son lecteur | Outils locaux, sans synchronisation |

**Important :** la configuration `storageService.enabled=false` de
`app.storage_agent` signifie qu'un simple `pkgctl install preset.storage`
ne donne *pas* accès à un stockage distant. Il faut configurer explicitement
le service, les permissions par action, les autorisations par pair/namespace
et les règles d'authentification SDK avant les premiers essais.

Les données persistantes sont, selon le backend :

- `/var/lib/storage/store.json` sur le disque interne ;
- `<montage>/attacc/storage/store.json` sur un `drive` CC reconnu et monté.

Limites initiales du backend : **4096 octets JSON par valeur**, jusqu'à
**512 clés**, et **32768 octets par valeur** pour les namespaces spécifiques
`attacc.config` / `attacc.events`. Le serveur réécrit une base JSON complète
avec un fichier temporaire `.new` ; ce n'est pas une base de données de
logs volumineux et il faut garder assez d'espace pour ce fichier temporaire.

Le `store.json` historique n'est pas un montage `fs` distribué.
Le service SDK signé et le service historique 4255/4256 ne sont pas
interchangeables en l'état.

## 2. Ce qu'on ne peut pas appeler « NAS » aujourd'hui

- Pas de `list directory`, `stat`, `read file chunk` ou `write file chunk`
  génériques sur un arbre de fichiers distant.
- Pas de montage transparent `/net` reconnu par l'API CraftOS `fs`.
- Pas de mise en cache locale de fichiers, reprise de transferts,
  quota par application ou mécanisme d'archivage de logs distants.
- Pas de répartition automatique de la place disque entre machines.
- Une application doit appeler les APIs de stockage explicitement ;
  `/run/attacc/state.json` ne doit pas être déplacé vers un serveur réseau
  pendant que les instantanés SDK fonctionnent.

## 3. Architecture recommandée pour la suite

```text
CC autonome A       CC SteamPlant        CC Pocket / Master
    |                     |                      |
    +----------- SDK network / auth -------------+
                          |
                 CC Storage (dédiée)
                 app.storage_agent
                       |
                Storage backend
            local HDD / CC disk drive
```

Le stockage doit être **un service SDK autonome**, au même titre que le
nouveau WebBridge, et ne doit jamais nécessiter la présence de Master.
WebBridge n'est pas non plus le serveur de stockage.

### Étape A : fiabiliser la petite base partagée

Faire une recette de `app.storage_agent` sur une CC dédiée :
découverte sans Master, authentification SDK, namespaces avec permissions,
`ping/list/get/set/delete`, persistance après reboot et backend sur disque CC.
Mesurer consommation et latence. Conserver la convention actuelle
`storage_request` signé.

### Étape B : décider s'il faut vraiment un stockage de fichiers

Si l'objectif inclut des fichiers transférables / sauvegardes / archives :
concevoir un service SDK de fichiers séparé, avec des opérations typées :

```text
list, stat, readChunk, writeChunk, mkdir, rename, delete
```

Imposer un répertoire de base autorisé, des quotas par pair, une taille de
bloc faible (par exemple 2 KiB, à confirmer en jeu), une somme de contrôle,
la reprise des transferts et des erreurs claires si le disque distant est
absent. Ne pas introduire de faux `fs.mount()` : CraftOS ne fournit pas une
API standard de montage réseau par défaut.

### Étape C : intégration aux applications

Définir une bibliothèque `lib.sdk_file_client` puis éventuellement des
commandes `storagectl` dédiées aux fichiers. Les applications choisissent
explicitement quelles données exporter. Les télémétries temps réel restent
sur le SDK transport ; les caches graphiques restent courts et locaux.

## 4. Priorité fonctionnelle confirmée : configurations et sauvegardes

**Décision du 19 octobre 2026 :** la première fonction de Storage est de
**centraliser les configurations des machines AttaCC, les sauvegarder et les
restaurer**. Un NAS de fichiers est souhaité **dans un second temps**, comme
extension facultative, et ne doit pas retarder ou déstabiliser la gestion des
configurations. Le design et le backend web sont hors périmètre.

### 4.1 Contrat du premier lot : Config Storage SDK

Réutiliser `app.storage_agent`, `core/sdk_storage.lua` et le backend
`modules/storage/backend.lua`, **sans nouveau protocole radio**.

- Un hôte Storage **indépendant de Master**, avec stockage local ou lecteur
  de disque CC et publication d'état via le SDK.
- Séparation entre la **configuration courante** et les **snapshots
  historiques** : par exemple namespaces `attacc.config` et
  `attacc.backups`. Ce sont des espaces d'identifiants, pas des dossiers
  de système de fichiers distant.
- Identité de chaque jeu de sauvegardes : `network` + clé machine stable
  + date/numéro de révision. Ne jamais restaurer automatiquement une autre
  machine lorsque les `computerId` physiques diffèrent.
- Données prioritaires : `/etc/machine.lua`, `/etc/apps.lua`,
  `/etc/io.lua`, `/etc/profile.lua` hérité, configurations spécifiques
  des applications dans `/etc/attacc/apps/` et politiques globales
  dans `/etc/attacc/system.lua` **si leur inclusion a été autorisée**.
  Les secrets d'authentification, tokens WebBridge, clés SDK et configs
  de stockage sensibles ne sont **pas inclus par défaut**.
- Lecture et sauvegarde via des **commandes SDK signées**, avec vérification
  de l'origine et permissions limitées par machine/namespace. Ne pas
  rediriger `profilectl push` vers le protocole non signé historique en
  l'appelant « SDK ».
- `backup` manuel et sauvegarde après modification de configuration
  deviennent la base. Une sauvegarde périodique/au reboot pourra être
  activée explicitement plus tard.
- Politique de rétention **bornée et configurable** (par défaut proposé :
  cinq révisions par machine), limites de taille adaptées au petit disque
  CraftOS, et restauration avec contrôle de checksum et confirmation.
- **La restauration ne se confond pas avec la synchronisation** :
  afficher la source, la destination, la date et les fichiers changés
  avant d'écraser les fichiers locaux ; faire une copie locale de sécurité
  avant toute restauration. Ne jamais écraser automatiquement
  `/etc/machine.lua` pour une autre clé machine.
- En absence de Storage : l'application continue à fonctionner sur
  ses configurations **locales** et signale seulement que le backup
  distant est indisponible. Aucune dépendance réseau au démarrage de
  SteamPlant.
- Les données `/run/attacc/state.json` et les caches `display/publish`
  sont **exclues** : ce sont des états temporaires qui avaient déjà
  provoqué des saturations disque.

### 4.2 Points réels à migrer dans le dépôt

Les fonctions `profilectl push/pull` de `core/profile_store.lua`
utilisent encore les canaux historiques `4255/4256` et stockent la
dernière version à `profile:<machine-key>` et
`machine:<machine-key>`. Elles ne constituent **pas** actuellement des
sauvegardes versionnées via le SDK signé.

`app.storage_agent` fournit les opérations signées
`ping/namespaces/list/get/set/delete`, mais aucune commande
`backup/list-revisions/restore-revision` intégrée à `profilectl`
ou `storagectl` n'a été créée ici. Le backend garde une seule valeur
courante par clé : **ne pas promettre de récupération d'une version
antérieure qui n'a pas été sauvegardée**.

Ordre des travaux :

1. Tester l'hôte Storage SDK sur CC dédiée (découverte, permissions,
   backend disque, persistance) et son `storage_request`.
2. Créer un **service de sauvegardes de configurations** qui écrit une
   nouvelle révision sans écraser la précédente et valide taille,
   origine, intégrité et rétention.
3. Brancher `profilectl` / les applications SDK sur ce service en
   gardant la compatibilité des fichiers locaux et en retirant la
   nécessité du modem historique pour les **nouvelles** opérations.
4. Ajouter les commandes `backup`, `list`, `diff`, `restore`,
   avec rollback de restauration et tests après reboot.
5. Seulement ensuite concevoir le serveur de **fichiers NAS** comme
   extension séparée.

### 4.3 Extension NAS ultérieure

Le NAS hébergera des **fichiers** (backups complets, scripts partagés,
archives, logs), pas les clés de configuration en tant que fichiers
synchronisés magiquement. Le même hôte CC pourra faire tourner
`app.storage_agent` et un service SDK de fichiers, mais chacun gardera
ses quotas, APIs, permissions et rétention. Le premier jalon du NAS
sera un transfert de fichiers explicite par blocs avec vérification et
reprise, **pas un faux montage `fs`**.

## 5. Points à préciser au moment de la recette



Avant d'implémenter un NAS, définir le besoin exact :

1. Partage de **configurations et états** (la base existante suffit largement)
   ou partage de **vrais fichiers/dossiers** ?
2. Disque CC local, lecteur `disk` monté, ou backend externe HTTP ?
3. Un seul hôte de stockage par réseau logique ou plusieurs destinations
   explicitement sélectionnées ?

Ces réponses déterminent la suite. Aucun routage de fichiers ni changement
de protocole de stockage n'a été appliqué dans cette passe.
