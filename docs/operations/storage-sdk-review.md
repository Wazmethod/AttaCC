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

## 4. Décisions encore nécessaires

Avant d'implémenter un NAS, définir le besoin exact :

1. Partage de **configurations et états** (la base existante suffit largement)
   ou partage de **vrais fichiers/dossiers** ?
2. Disque CC local, lecteur `disk` monté, ou backend externe HTTP ?
3. Un seul hôte de stockage par réseau logique ou plusieurs destinations
   explicitement sélectionnées ?

Ces réponses déterminent la suite. Aucun routage de fichiers ni changement
de protocole de stockage n'a été appliqué dans cette passe.
