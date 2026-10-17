# AttaCC SDK 1.1 — recette Minecraft (à exécuter une fois la stabilisation terminée)

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

**Revalidation ciblée** : actualiser `core.runtime` après mise à jour du dépôt HTTP, redémarrer SteamPlant puis observer `/df` depuis `/run/attacc` après 1, 3 et 5 minutes d'utilisation. Vérifier également `/du` dans `/run/attacc` et `/run/attacc/display` pour constater que les fichiers se stabilisent. Master/Pocket doivent continuer d'afficher leurs courbes et d'actualiser leurs snapshots. Correctif non encore validé dans CraftOS.

## Diagnostic du stockage après R-12/R-17

Les outils CraftOS du package `core.runtime` suivent une convention sans options :

- `du` : tailles des fichiers et sous-dossiers du répertoire courant, avec calcul récursif, tri décroissant et indication des fichiers illisibles.
- `df` : lecteur et point de montage du répertoire courant, capacité totale, espace utilisé et libre ; aucune exploration des fichiers.

Sur SteamPlant, entrer `cd /var/log` puis lancer `/du` et `/df`. Pour un disque monté, entrer `cd /disk` puis `/df`. Les commandes `/du` et `/df` restent utilisables depuis n'importe quel dossier sans dépendre du PATH. La taille des fichiers dans `du` n'est pas nécessairement l'espace utilisé indiqué par `df`, notamment en présence de plusieurs points de montage.

Les outils sont poussés sur GitHub mais cette révision reste à valider en jeu.

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
