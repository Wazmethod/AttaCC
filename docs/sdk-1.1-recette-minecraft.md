# AttaCC SDK 1.1 — recette Minecraft et retours de validation

> **Statut : première recette effectuée le 17/10/2026 ; correctifs de suivi en cours.** Détails des résultats ci-dessous.
> Branche cible : `feature/v1.1-sdk-unification`. Aucun merge vers `main` avant validation.

## Premier compte rendu en jeu — 17 octobre 2026

Le premier test réel **n'est plus « non exécuté »** : Master, Pocket et SteamPlant ont démarré. Le problème initial de sérialisation WebCap est résolu sur les CC testées. Ne pas confondre le démarrage validé avec la validation de toutes les interactions.

| Scénario | Retour utilisateur | Suite |
| --- | --- | --- |
| R-01 | **OK** — les trois applications démarrent | Acquis |
| R-02 | **Partiel** — navigation et disposition bonnes ; graphes SteamPlant visibles en sélectionnant Master/Pocket | Retirer les graphes miroirs et revérifier |
| R-03 | **OK fonctionnel** — texte/graphique et commandes fonctionnent ; style texte à améliorer plus tard | Cosmétique, non bloquant |
| R-04 | **OK fallback** — moniteurs 1×1 à 3×2 parfois trop petits ou compressés ; pas de crash | Garder le fallback texte et le reboot après changement, revoir l'échelle séparément |
| R-05 | **Non testé** | Tester après création d'une nouvelle app SDK |
| R-06 | **Partiel** — pagination correcte, graphes de mauvaise source | Vérifier après suppression des graphes miroirs |
| R-07 | **OK** — données cohérentes | Rotation/configuration SteamPlant à ajuster plus tard |
| R-08 | **OK** — courbes cohérentes, batterie en charge | Acquis |
| R-09 / R-10 | **OK rapporté** — simple clic et confirmation pour actions sensibles | Acquis |
| R-11 | **OK** — PENDING, TIMEOUT, ACK reçus | Acquis |
| R-12 | **Partiel** — source stale à 12 secondes, commande bloquée, mais sans toast | Rendre les boutons gris explicatifs |
| R-13 | **OK** — confirmation non transférée en changeant de source | Acquis |
| R-14 | **Semble OK** — pas de doublon visible ; vérification des timestamps non instrumentée | À confirmer si nécessaire |
| R-15 | **OK** — embrayages fonctionnels, redémarrage automatique réussi | Acquis |
| R-16 | **OK** — démarrage et ABORT satisfaisants | Acquis |
| R-17 | **KO** — aucune donnée dans EVENTS sur Master/Pocket | Publier les événements SteamPlant vers `app.event` via réseau SDK |
| R-18 | **OK** — redémarrage, données et commandes reviennent | Acquis |
| R-19 | **OK** — bascule et fallback texte fonctionnent | Acquis |
| R-20 | **OK** — `pkgctl` ne signale pas de problème | Acquis |

**Problème transversal urgent :** SteamPlant finit par s'arrêter avec `out of space`. La cause et les tailles de fichiers ne sont **pas encore connues** ; demander la capacité restante et la répartition de l'espace avant toute purge. Ne pas supprimer le journal, la configuration ou l'état persistant sans diagnostic.

**Correctifs poussés après ce retour :** suppression des graphes distants réexportés comme graphes locaux sur Master/Pocket ; Master : sélection uniquement dans MACHINE, SELECT désactivé pour la CC locale mais REBOOT conservé, libellé de machine sélectionnée et pagination native dans les catégories ; SteamPlant : événements `app.event` sur le réseau ; boutons distants inactifs : toast explicitant `SOURCE STALE` ou verrouillage. **Ces corrections restent à retester après mise à jour.**

---
## Retours complémentaires — stabilité réseau et stockage

- **R-12 : OK**. Arrêt d'une source SteamPlant : le statut devient stale après 12 secondes ; les contrôles sont bloqués et le toast `SOURCE STALE` apparaît.
- **R-17 : OK pour le transport**. Le nombre d'événements augmente désormais sur les clients Master/Pocket. Le style et le contenu détaillé des événements seront étudiés séparément.
- **R-02 / R-06 : OK après correctifs**. Master suit la disposition Pocket et les graphes SteamPlant n'apparaissent plus lorsque l'utilisateur choisit une autre machine ; la pagination reste cohérente.
- **Stockage SteamPlant, encore à surveiller**. Mesures successives du libre : `238245` puis `110756` octets. Les journaux `/var/log` occupent une part majeure des quatre dossiers mesurés ; la rotation AttaCC existe déjà, donc poursuivre l'observation avant de supprimer des fichiers.
- Outils de diagnostic fournis dans `core.runtime` : depuis `/var/log`, lancer `/du` pour les tailles récursives des éléments du répertoire courant, puis `/df` pour la capacité et l'espace libre du lecteur. Même principe depuis `/run/attacc`.
- **Projets ultérieurs non démarrés** : ajout éventuel de disque ou idée de NAS, thème Web synchronisé avec l'interface en jeu, développement d'une seconde application entièrement SDK.

## Correction de la saturation disque SteamPlant — cache SDK

Observation confirmée en jeu : `/run/attacc/state.json` et `/run/attacc/display/publish.json` grossissent pendant l'exécution de SteamPlant ; le volume occupé retombe autour de 77 % après arrêt/crash. Ce retour oriente vers les copies des descripteurs JSON publiés à chaque cycle, et non seulement vers les logs.

Le SDK conservait les **historiques entiers des graphiques** dans ces deux caches sur disque, ainsi qu'une seconde copie des collections dans `remoteExports`. Les graphes ont une limite en mémoire (`graph.limit`, jusqu'à 300 points) mais leur croissance peut épuiser l'espace libre avant cette limite. Les écritures `.new` consomment temporairement davantage de place.

Correctif dans `core/attacc.lua` : `app:publish()` utilise un descripteur de **cache persistant** contenant au maximum **8 échantillons par graphe** (y compris les exports graphiques distants), alors que `app:draw()` et `sdk_transport` gardent leurs données complètes en mémoire/réseau. Les commandes, vues et métriques demeurent inchangées ; seul l'historique visible en relisant un cache JSON persistent est plus court. Aucune donnée persistante existante n'est supprimée par migration.

**Revalidation en jeu : OK sur une heure d'utilisation.** SteamPlant a fonctionné pendant environ une heure sans nouveau crash ni saturation rapportée. Plusieurs exécutions successives de `/du` dans `/run/attacc` donnent les mêmes tailles : `state.json` **24,9 KiB**, sous-dossier `display/` **24,2 KiB**, total **49,1 KiB**. Le plafonnement des historiques dans les caches a donc le comportement attendu sur ce montage. Cela valide la stabilisation du volume des deux caches observés, mais ne constitue pas un essai d'endurance de plusieurs jours ni une mesure du stockage entier. **Prochaine étape :** deuxième application 100 % SDK pour vérifier la généricité du framework (R-05), puis clôture de la recette et validation éventuelle du merge par le propriétaire.

## Diagnostic du stockage après R-12/R-17

Les outils CraftOS du package `core.runtime` suivent une convention sans options :

- `du` : tailles des fichiers et sous-dossiers du répertoire courant, avec calcul récursif, tri décroissant et indication des fichiers illisibles.
- `df` : lecteur et point de montage du répertoire courant, capacité totale, espace utilisé et libre ; aucune exploration des fichiers.

Sur SteamPlant, entrer `cd /var/log` puis lancer `/du` et `/df`. Pour un disque monté, entrer `cd /disk` puis `/df`. Les commandes `/du` et `/df` restent utilisables depuis n'importe quel dossier sans dépendre du PATH. La taille des fichiers dans `du` n'est pas nécessairement l'espace utilisé indiqué par `df`, notamment en présence de plusieurs points de montage.

L'utilitaire `/du` a été utilisé avec succès sur SteamPlant pour contrôler la stabilité des caches. La commande `/df` est disponible ; son fonctionnement n'a pas été confirmé par ce retour.

## WebBridge autonome et revue Storage — découplage SDK

**Nouvelle cible fonctionnelle :** WebBridge ne doit plus dépendre de `app.master`, et la WebUI reste inchangée pour cette passe. Une CC peut héberger seule le relais, même si aucun Master n'est présent sur son réseau.

- Nouvelle application `app.webbridge` : propre host SDK, modems, souscriptions `node.status`, `app.event`, snapshots, WebSocket ; pas de dépendance à `app.master`.
- `app.master` ne crée plus de connexion WebSocket ni d'instance de relais ; la donnée de statut WebBridge se base sur la découverte SDK lorsqu'elle est disponible.
- `preset.webbridge` lance directement WebBridge sur une CC dédiée. Sur une CC hébergeant déjà Master, Pocket ou SteamPlant, `webbridgectl enable` prépare un démarrage dans un **onglet multishell séparé** après reboot, et `disable` le désactive.
- Le mode sidecar est `display=false,publishLocal=false` : il continue d'envoyer des snapshots réseau SDK, mais ne réécrit pas le cache JSON d'affichage local à la place de Master/SteamPlant.
- `webbridgectl` appartient désormais à `app.webbridge` et conserve le fichier existant `/etc/webbridge.lua`. Backend web et CSS inchangés. Relais WebBridge en mode `SDK READ ONLY`.
- La base de stockage existante a été auditée : `app.storage_agent` signé et indépendant (désactivé par défaut), ancien `storagehost` K/V sur canaux historiques, backend local ou disque, mais **pas de service de fichiers NAS**. `preset.storage` prépare une CC dédiée sans activer les écritures. Détails : `docs/operations/storage-sdk-review.md`.

**Recette non effectuée en jeu pour cette passe :**

1. Sur une CC Master existante, `pkgctl install app.webbridge` puis `pkgctl update core.runtime` et `pkgctl update app.master`, `webbridgectl enable`, `reboot`. Vérifier deux onglets indépendants.
2. Arrêter Master, conserver la CC WebBridge sur le réseau : `BRIDGE LINKED` doit rester présent et les données d'une CC SteamPlant doivent continuer de remonter.
3. Sur une CC sans Master, installer `preset.webbridge`, initialiser l'identité réseau, configurer `/etc/webbridge.lua`, activer le preset puis reboot. Vérifier la découverte SDK et la reconnexion.
4. Vérifier qu'une WebBridge colocataire n'écrase pas le cache local `display/publish.json` de l'application principale. Ne pas démarrer plusieurs relais pour le même réseau et le même backend pendant les essais.
5. Plus tard, décider si Storage doit servir une petite base partagée ou des vrais fichiers. Aucun transfert NAS n'a été implémenté.

## Interface Web OPERATIONS — fiche MACHINE unifiée et inventaire SDK automatique

**Retour en jeu du 18 octobre :** les axes X/Y s'affichent correctement, mais lorsque le graphe occupe une rangée entière, son tracé SVG reste centré et n'utilise pas sa largeur. L'utilisateur souhaite aussi inverser les colonnes INFORMATION et CODE dans EVENTS, supprimer le modal machine et ouvrir directement la fiche MACHINE d'OPERATIONS depuis NETWORK. L'onglet MACHINE présente 0 module / aucun package ni processus sur SteamPlant malgré l'application active.

**Correctifs intégrés :**
- `GraphChart` utilise une mesure réelle de la largeur et hauteur de son SVG (ResizeObserver avec fallback window.resize), et adapte la géométrie du graphe à l'espace disponible au lieu d'un dessin 600 px centré. L'axe X reste temporel. L'heure du dernier échantillon peut aussi servir à compenser un léger décalage entre CraftOS et le serveur.
- Les événements affichent désormais TIME, SOURCE, INFORMATION puis CODE, avec colonnes CSS responsives. Les messages longs se replient sans se mélanger au code.
- La vue MACHINE contient les diagnostics complets directement dans OPERATIONS : identité, version runtime, uptime, apps, modules, packages, onglets ouverts, télémétrie détaillée et journaux. Le modal a été supprimé ; un clic sur une machine depuis NETWORK ouvre OPERATIONS/MACHINE avec la bonne source, même lorsqu'aucune télémétrie applicative n'est encore arrivée.
- La collecte d'informations machine devient **automatique pour toute application SDK** via `lib.system_snapshot.compact(app.id)`, sans déclaration manuelle de champs `app:data`. Les annonces sont limitées et cadencées à 15 s pour l'inventaire et 2 s pour la présence : version de `core.runtime`, nombre et liste des packages (maximum 48 détaillés), applications (maximum 20 détaillées), modules, onglets/processus CraftOS (maximum 16), quelques logs, disque principal et identifiant CC. Le nombre total reste exact lorsque la liste est tronquée.
- Le WebBridge Master transmet ces inventaires vers le backend existant. Les listes simples de noms `apps/modules` restent compatibles avec NETWORK, les objets enrichis étant dans `system`. Le backend conserve le dernier inventaire pendant les annonces de présence.

**À valider après déploiement :** tester l'étirement des graphes sur une rangée entière ; contrôler l'ordre des colonnes EVENTS ; cliquer SteamPlant dans NETWORK et vérifier qu'OPERATIONS/MACHINE s'ouvre sans popup ; vérifier sur Master et SteamPlant le nombre de packages, `core.runtime` version et les onglets ouverts après ~15–30 secondes. Les inventaires SDK nécessitent une mise à jour `core.runtime` de **chaque CC**, et `app.master` sur Master. Rebuild de `web` nécessaire pour le frontend. Ces changements ont été vérifiés statiquement mais pas encore exécutés en jeu.

## Interface Web OPERATIONS — axes, données, EVENTS et MACHINE

**Retour utilisateur après première refonte :** sur SteamPlant, les graphes affichent par exemple `100 → 101` sous la courbe, même lorsque la donnée reste à 100 %, et l'axe temporel n'est pas indiqué. Sur Master, environ 35 données sont présentées dans un seul ensemble sans catégories. Le modal MACHINE accessible depuis NETWORK ne reçoit pas l'inventaire complet de la CC (versions, applications, modules, processus, packages). L'utilisateur demande des onglets EVENTS et MACHINE directement dans OPERATIONS.

**Correctifs poussés, pas encore testés dans le navigateur / CraftOS :**
- `GraphChart` trace l'axe horizontal en **temps relatif** (fenêtre `timeWindow` SDK, 120 s par défaut), et l'axe vertical en **valeurs réelles** (bornes `min/max`, si elles sont déclarées), avec graduations dans le SVG. La conversion `Number(null)` en zéro implicite est évitée ;
- `sdk_snapshot.compat` transporte désormais les bornes et durées des graphes ainsi que les libellés des booléens ; les valeurs DATA `true/false` sont visibles sur le site ;
- Master et Pocket enregistrent leurs champs DATA dans des catégories SDK explicites (SUPERVISION, SOURCE, NETWORK, EVENTS, MACHINES, etc.). Les valeurs textuelles longues prennent toute la largeur de la grille web ;
- nouveaux onglets `EVENTS` (historique filtré sur réseau + machine + module) et `MACHINE` (résumé + ouverture du modal existant), sans duplication du code de NETWORK ;
- les SDK hosts transmettent périodiquement un **inventaire système compact**, toutes les 15 s (jusqu'à 24 apps/modules, 16 processus, 80 packages et huit logs raccourcis). Le service de découverte et le backend conservent les derniers inventaires entre les annonces rapides de présence. Master inclut son inventaire local dans le WebBridge.

**Scénarios de contrôle :** reconstruire `web` et recharger le navigateur ; sur SteamPlant vérifier RPM/LOAD/WATER/HEAT/BATTERY avec des axes `-120s..0s` et Y `0..100` pour les pourcentages ; changer d'application et vérifier les groupes DATA de Master/Pocket ainsi que les booleéns ; consulter EVENTS en déclenchant un événement SteamPlant ; ouvrir MACHINE, puis son modal, et vérifier qu'APPS, MODULES, PROCESSES, PACKAGES se remplissent. La réception d'inventaire système nécessite de mettre à jour `core.runtime` et de redémarrer les applications des CC ; Master doit aussi recevoir `app.master`.

## Interface Web OPERATIONS — réorganisation après retour en jeu

**Retour utilisateur :** après redémarrage de Master, la page web affiche correctement `BRIDGE LINKED` et `WEB CONNECTED`, les applications SteamPlant, Master et Pocket remontent avec leurs métriques, graphiques et états. Le WebBridge est donc **validé pour la supervision**. Le défaut restant est ergonomique : la page OPERATIONS alignait toutes les applications dans des colonnes étroites, en laissant de grands espaces vides et en comprimant les graphes SteamPlant.

**Refonte appliquée au site uniquement :**
- panneau SOURCES avec liste des applications et recherche, état LIVE/STALE, réseau, machine et compteurs ;
- un **seul panneau détaillé** pour l'application sélectionnée, affichée dans toute la largeur utile ;
- onglets internes `DATA`, `GRAPHS`, `CONTROLS`, sans étirer les applications dépourvues de graphes ;
- données regroupées par catégories SDK lorsqu'elles existent ; graphiques plus larges ; responsive vertical sur tablette/mobile ;
- les boutons de commande restent désactivés quand le SDK WebBridge fonctionne en lecture seule ; aucune modification de l'automatisme SteamPlant ou de Master/Pocket.

**Test ciblé après rebuild web :** OPERATIONS doit sélectionner par défaut une application avec graphe (SteamPlant), puis permettre de passer à Master et Pocket sans valeurs fantômes. Confirmer les trois onglets, l'affichage des courbes en évolution, la recherche et la disposition en fenêtre étroite. La navigation vers OVERVIEW, NETWORK, LOGS, DOCS et REPOSITORY doit rester inchangée. **Cette nouvelle disposition n'a pas encore été validée dans le navigateur.**

## WebBridge SDK et interface web — passe de restauration

Suite au passage de Master à `app.master` SDK-native, le WebBridge historique ne se lançait plus. Résultat en jeu : Master fonctionnel, mais interface web affichant `BRIDGE OFFLINE`, sans nœuds ni télémétrie.

**Correction sur la branche de stabilisation :**
- Le Master SDK charge `lib/sdk_master_webbridge.lua` et démarre automatiquement le WebSocket si `/etc/webbridge.lua` est configuré. Il n'ouvre aucun second modem ni aucune boucle applicative parallèle.
- Les annonces `node.status`, `attacc.sdk.snapshot.v1` et `app.event` sont relayées au backend avec ses formats existants `node_status`, `telemetry` et `event`. Les métriques de Master sont également diffusées.
- Le serveur expose `commandsEnabled` dans `/api/status` et distingue les bridges SDK en mode lecture seule. Les anciens endpoints de contrôle refusent les commandes plutôt que de répondre faussement `SENT`.
- Le Web reprend le style AttaCC en jeu : noir/graphite, panneaux gris, boutons sélectionnés cyan, valeurs jaunes, alertes rouges. Les pages et fonctions du catalogue et de la documentation restent inchangées.

**À tester :** avec les mêmes URL et secrets `MACHINE_TOKEN` qu'avant, actualiser `app.master` sur la CC Master, redémarrer son app, reconstruire le conteneur `web` puis confirmer `WEB CONNECTED` et `BRIDGE LINKED` dans le navigateur. Les cartes MACHINES, OPERATIONS (télémétrie uniquement) et LOGS doivent se remplir et s'actualiser. Vérifier également la reconnexion après arrêt/redémarrage de Master, et que l'interface désactive correctement les commandes avec `SDK READ ONLY`. **Retour en jeu ultérieur :** BRIDGE LINKED et WEB CONNECTED confirmés sur le site, télémétrie SteamPlant / Master / Pocket reçue. La restauration de la supervision est donc validée ; les commandes SDK depuis le web restent explicitement désactivées.

**Limite assumée :** la supervision est rétablie en priorité ; les commandes web historiques ne sont pas encore adaptées au système de commandes SDK signé et ne sont donc pas activées. Aucun downgrade non authentifié vers le protocole historique.

## 1. Préparer les CC et le monde

Prévoir un monde sauvegardé et une copie récupérable des ordinateurs (disques de CC et fichiers persistants) **avant** les mises à jour. Noter la source de déploiement initiale et les versions qui fonctionnent déjà : revenir simplement sur `main` ne constitue pas à lui seul une restauration garantie.

Prévoir au minimum une CC SteamPlant connectée à son montage Create, une CC Master et une Pocket Computer. Toutes les CC doivent être sur le même réseau AttaCC et disposer des modems nécessaires. Prévoir un moniteur avec CC:Graphics, un moniteur texte et, si possible, un petit moniteur.

**Attention :** ne pas activer de commandes de sortie tant que la configuration des rôles I/O de SteamPlant n'a pas été revue. `appctl check steamplant` est un précontrôle en lecture seule, pas un essai de démarrage.

## 2. Vérifier la source de paquets avant toute mise à jour

Sur chaque CC, afficher et tester la source actuellement choisie :

```text
pkgctl source show
pkgctl source test
pkgctl status
```

Si la CC utilise le serveur HTTP AttaCC (`/repo`), vérifier côté serveur qu'il publie **bien la révision** de `feature/v1.1-sdk-unification` ; la commande `source branch` ne remplace pas la source HTTP personnalisée.

Pour une CC qui utilise explicitement GitHub (et non un serveur HTTP personnalisé) :

```text
pkgctl source github
pkgctl source branch feature/v1.1-sdk-unification
pkgctl source test
```

Les versions et le contrat attendus du manifeste sont : SDK API `1.1`, snapshots `1`, commandes `1`, affichage `2`. En cas d'échec HTTP, de branche erronée ou de contrat inattendu, **ne pas poursuivre l'installation**.

## 3. Déployer l'ensemble cohérent

Sur les ordinateurs déjà équipés des packages et presets correspondants :

```text
pkgctl update
pkgctl status
```

Au besoin, installer le preset correspondant à une CC nouvellement configurée : `preset.steamplant`, `preset.master` ou `preset.pocket`. Un redémarrage des applications après la mise à jour est nécessaire pour recharger les modules Lua.

Vérifier que `core.runtime`, `module.display`, `module.network`, l'application et le gestionnaire de packages proviennent de la **même source/révision**. Les dépendances communes ne devraient être téléchargées qu'une fois pendant `pkgctl update` global. Aucun GitHub Actions n'est nécessaire.

## 4. Vérifier le SDK sans démarrer les sorties

```text
appctl check steamplant
appctl check master
appctl check pocket
```

Chaque commande est destinée à sa CC respective. Vérifier les dépendances et les rôles matériels attendus. Si une CC échoue au précontrôle, relever exactement la ligne indiquant la dépendance ou le matériel manquant et corriger la configuration avant le lancement.

Puis démarrer les applications selon la configuration de preset déjà utilisée (ou `appctl <app-id>` pour un lancement manuel), sans installer de daemon supplémentaire.

## 5. Scénarios de validation en jeu

| ID | Scénario | Résultat attendu |
| --- | --- | --- |
| R-01 | Démarrage SteamPlant/Master/Pocket | Pas d'erreur Lua, titre et vue initiale cohérents |
| R-02 | Moniteur CC:Graphics : vues et sous-vues | Navigation entre HOME/MACHINE/DATA/GRAPHS/CONTROLS sans blocage |
| R-03 | Moniteur texte : vues et pagination | Même contenu utile, sans pages vides inutiles |
| R-04 | Petit moniteur en mode texte | Navigation et valeurs lisibles sans débordement fatal |
| R-05 | Deux applications SDK publiées sur une même CC | Master/Pocket permettent de voir les deux si les trames arrivent réellement |
| R-06 | Sélection d'une nouvelle source en page avancée | Retour à la première page de sa vue, source correcte |
| R-07 | Données DATA et catégories | Valeurs, unités, labels et catégories concordent avec l'émetteur |
| R-08 | Courbes GRAPHS | Valeurs actualisées et anciennes mesures retirées selon `timeWindow` |
| R-09 | Bouton tactile local `confirm=false` | Une pression suffit |
| R-10 | Bouton tactile local `confirm=true` | Double pression et message de confirmation |
| R-11 | Bouton distant Pocket/Master | Identifiant stable, confirmation, puis ACK/erreur affiché |
| R-12 | Source devenue inactive (`staleMs`) | Contrôles distants non disponibles jusqu'au retour de la source |
| R-13 | Changement de source pendant une confirmation | L'ancien bouton n'agit pas sur la nouvelle source |
| R-14 | Réception des snapshots en double | Aucun point graphique dupliqué avec le même timestamp |
| R-15 | SteamPlant : état et commandes de clutch | États lus et changements constatés physiquement dans Create |
| R-16 | SteamPlant : procédure de démarrage/interruption | États et erreurs affichés correctement ; pas de blocage majeur |
| R-17 | Master/Pocket : événements de réseau | Événements de la bonne machine/app et absence d'échos indésirables |
| R-18 | Réouverture/redémarrage des programmes | Sources, versions et interfaces toujours disponibles |
| R-19 | Retour au mode texte si CC:Graphics échoue | Aucun crash, données du même rafraîchissement |
| R-20 | `pkgctl status` après redémarrage | Pas de fichiers manquants et versions cohérentes |

Le comportement des clutches n'a **pas** à être parfaitement résilient à chaque panne improbable : une commande qui échoue peut être rejouée manuellement. L'objectif est un fonctionnement confortable et compréhensible pour Minecraft.

## 6. Critères de passage et relevé de bugs

Pour chaque scénario, noter : CC concernée, preset, version/source, taille du moniteur, action réalisée, résultat observé, et texte exact des erreurs Lua ou logs éventuels.

Critère de passage : aucune erreur bloquante de chargement/runtime, navigation et commandes usuelles fonctionnelles, données et graphes cohérents, dépendances installées et source connue. Les limites cosmétiques mineures peuvent être notées pour la version suivante.

La validation finale du SDK se fera ensuite **en développant une nouvelle application entièrement SDK** ; c'est une étape distincte de cette recette fonctionnelle.

## 7. Retour arrière

Si un incident bloque le démarrage, stopper l'application concernée et **restaurer la copie du monde/des ordinateurs prise avant la mise à jour**. Ne pas compter sur un simple changement de branche de `pkgctl` pour rétrograder correctement un lot de fichiers incompatibles.

Ne fusionner sur `main` qu'après validation explicite des résultats et traitement des régressions bloquantes.
