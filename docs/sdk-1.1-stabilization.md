# AttaCC 1.1 SDK — stabilisation et migration

Document de suivi de l'audit technique du 17 octobre 2026. Branche d'intégration : `feature/v1.1-sdk-unification`.
Ne pas considérer cette branche comme stable avant une recette en jeu.

## Corrections effectuées

- **A-03 (P2)** : `sdk_snapshot.frame()` ajoute `descriptor.exportWarnings.truncated` quand les limites de 64 DATA, 64 GRAPHS, 64 CONTROLS ou 16 VIEWS sont dépassées. La compatibilité des anciennes trames est préservée. Le réseau conserve ses limites : les entrées excédentaires ne sont pas transmises.
- **A-14 (P2)** : `sdk_system_config.load()` rejette les échelles incompatibles avec CC:Tweaked et les décalages tactiles non entiers ou hors limites ; les noms de moniteur contenant des caractères de contrôle sont rejetés.
- **Validation** : vérifications manuelles regroupées en fin de stabilisation, sans GitHub Actions.

- **A-09 (P1, implémenté, à valider en jeu)** : suppression des contrôles intermédiaires `remote_export_N` de Pocket et Master ; les boutons graphiques transmettent désormais directement l’identifiant exporté. Le SDK confirme la cible sélectionnée et revérifie l’export et les autorisations avant tout envoi. La confirmation tactile est liée à l’identité machine/application. Le module partagé `lib/sdk_remote_controls.lua` résout les identifiants.

- **A-13 (P2, partiel)** : l’accès aux valeurs d’affichage système est désormais basé sur un unique chargement validé ; `displayExplicit` distingue les propriétés réellement configurées des valeurs par défaut. Le cache/rechargement explicite reste à étudier.
- **A-01 (P1, partiel)** : les groupes de catégories sont conservés dans la compatibilité des snapshots ; le reste de la parité des vues est à vérifier.

- **A-18 (P1, partiel)** : manifeste doté du contrat `sdk={api="1.1",snapshot=1,commands=1,display=2}` ; `pkgctl` rejette un manifeste annonçant un autre contrat avant de télécharger ou remplacer les fichiers. Les anciens manifestes sans contrat restent pris en charge. Cela **ne garantit pas** encore la compatibilité de plusieurs versions déjà installées sur des machines différentes.
- **A-02 (P2, contrat)** : les vues personnalisées locales ne sont pas des écrans graphiques transportables : seul leur descriptif léger et les exports DATA/GRAPHS/CONTROLS sont partagés. Pocket/Master reconstruisent leur rendu.

- **A-03 / A-01 (diagnostics)** : les snapshots rejettent désormais les entrées exportées malformées avec une erreur précise, et leurs avertissements de troncature remontent également dans la télémétrie de compatibilité. Les plafonds de transport restent inchangés.
- **A-13 (cohérence)** : `sdk_system_config.load()` renvoie aussi `displayExplicit={}` en absence de fichier système, permettant de conserver le comportement de repli vers la configuration applicative.

- **A-01 (parité complémentaire)** : les contrôles internes `uiHidden=true` ne figurent plus dans l’interface de compatibilité. L’état et les libellés ON/OFF des contrôles sont préservés pour les clients qui consomment ce format. Ces champs sont additifs et n’activent aucune commande.

- **A-18 / A-01 (réception des snapshots)** : la conversion de compatibilité rejette les identités vides, les collections d'exports de type incorrect et les désaccords entre l'en-tête et le descriptif (`schema` et `module`). Les anciens champs facultatifs restent facultatifs.

- **A-17 (P1, implémentation partielle, à valider en jeu)** : `running_topology` exige maintenant l'initialisation du contrôleur ainsi que des mesures RPM/capacité au moins égales aux seuils `detection.onlineRpm` et `detection.onlineCapacity`. `all_cut` conserve son accès sans cette condition. Les commandes de topologie et d'embrayage refusent désormais de déclarer un succès lorsque l'écriture signale une erreur. Le scénario réel et le comportement en cas d'application partielle doivent rester dans la recette finale.

- **A-16 (P1, partiel)** : `abort` tente toujours l'arrêt du moteur et la coupure de l'embrayage générateur, mais signale désormais `AUTO_ABORT_INCOMPLETE` et un échec de commande si l'une des écritures échoue. L'état physique reste à contrôler dans la recette en jeu.

- **A-16 (P1, reprise automatique)** : `stopBlackStartDrive()` signale maintenant les échecs d'arrêt moteur ou de coupure du générateur (`STARTUP_STOP_INCOMPLETE`). La logique de nouvelle tentative renonce à programmer un redémarrage automatique si cet arrêt échoue, et passe à l'état `ERROR`. Scénario à vérifier lors de la recette Minecraft finale.

## Consolidation des séquences automatiques — A-16 / A-17

Le contrôleur traite désormais comme des erreurs les échecs d'écriture pendant la phase `AUTO_VERIFY` : embrayages principal/générateur/alternateur et arrêt moteur. La transition et la confirmation physique de `RUNNING` ne doivent pas masquer ces erreurs. La commande de maintien de l'alternateur vérifie elle aussi sa réussite ; une erreur pendant une procédure automatique interrompt la séquence et passe par le traitement de reprise.

`latchAlternator()` n'annonce une activation qu'après réussite de l'écriture. Les appels de transfert et de confirmation `RUNNING` vérifient sa réponse. Un `abort` dont l'arrêt moteur ou la coupure générateur échoue met le contrôleur en `ERROR` ; une relance automatique n'est pas programmée quand le moteur de démarrage ne peut pas être arrêté.

`running_topology` déclare dans l'application ses dépendances en capteurs et sorties, en plus des conditions RPM/capacité vérifiées dans le contrôleur. `all_cut` reste indépendant de la disponibilité des capteurs, pour ne pas désactiver inutilement cette commande. Les écritures multiples ne sont **pas atomiques** : une panne sur la deuxième ou troisième sortie peut laisser une topologie partiellement appliquée. La recette en jeu doit couvrir ce cas avant toute validation du système.

Ces corrections restent **non testées dans Minecraft**. Aucun changement de montage ou de câblage n'est présumé.

## Revue consolidée des défauts SteamPlant (A-16 / A-17)

- `ALL_CUT` tente l'arrêt du moteur puis la coupure des **trois** embrayages, même si une des opérations précédentes échoue. Toute opération défaillante retourne un échec et provoque `ALL_CUT_INCOMPLETE` avec passage à `ERROR`. Une réussite d'API ne vaut pas confirmation physique.
- Une erreur bloquante déjà signalée par l'état `ERROR` n'est plus effacée automatiquement par la détection d'une panne de la centrale, ni suivie d'une nouvelle tentative automatique dans ce cas. Une action explicite de l'opérateur reste nécessaire.
- Les étapes `AUTO_VERIFY`, le maintien de l'alternateur et les arrêts de démarrage prennent les retours d'échec en compte. Une erreur d'arrêt empêche la relance automatique.
- Les sorties de `TRANSFER`, `RUNNING` et `BLACK_START` ne sont toujours **pas transactionnelles** : les sorties précédemment modifiées ne sont pas restaurées automatiquement en cas d'échec ultérieur. Ne pas supposer un retour arrière implicite.
- **Recette obligatoire en jeu** : vérifier les réactions des clutches et du moteur, la persistance des erreurs, l'arrêt complet, la reprise après erreur, l'application partielle d'une topologie et l'exécution simultanée depuis Master et Pocket.
- **Compatibilité entre versions** : le manifeste déclare le contrat SDK mais ce mécanisme ne synchronise pas automatiquement les versions déjà installées sur les différentes CC. Déployer le runtime et les clients de la même révision avant d'activer les commandes distantes.

## Simplification et ergonomie Minecraft — passe complémentaire

- **A-01 (exports)** : `app:descriptor()` fournit par défaut les exports structurés `DATA`, `GRAPHS` et `CONTROLS` au renderer. `setRemoteExports()` peut remplacer un groupe sans supprimer les autres. `buildDashboard()` reste une option pour **créer les vues locales** : les vues personnalisées ne sont pas copiées à distance.
- **A-09 (simplification)** : `sdk_remote_controls.lua` ne garde que le lookup par identifiant ; les anciens résolveurs de numéros de cases sont supprimés.
- **A-10 (affichage)** : la pagination des groupes est calculée selon la hauteur de carte réellement disponible, y compris la place prise par les boutons d'action. Les lignes de fin ne doivent plus disparaître lorsqu'un groupe dépasse la capacité d'une carte. Les graphiques utilisent également la hauteur utile après la barre d'actions.
- **A-16 (toggles)** : les commandes de toggle de clutch relisent l'état via le module `outputs` au lieu de se baser uniquement sur la télémétrie du cycle précédent. Les autres mesures conservent leur rythme de collecte habituel.
- **A-03 (diagnostic)** : Pocket et Master signalent une troncature d'exports une fois lors de son apparition sur une source ; pas de toast répété à chaque snapshot.
- **A-18 (déploiement)** : `pkgctl source test` affiche aussi la source/branche et les versions de contrat SDK annoncées dans le manifeste.

Le choix reste volontairement léger : **Minecraft/CC:Tweaked**, pas de mécanisme supplémentaire de protection de chaque clutch. Aucun test en jeu ni merge vers `main` à ce stade ; tous les cas de tactile, de graphes, de catégories et de toggles seront réunis dans la recette finale.

## Navigation des sources et commandes visibles — Master / Pocket

- Les vues `MACHINE` et leurs sous-vues `DATA`, `GRAPHS`, `CONTROLS` disposent d'une navigation de source.
- **Master** : les commandes `previous_source` et `next_source` parcourent maintenant les identifiants d'applications complets, et non plus seulement le nom de la machine. Une machine qui publie plusieurs applications devient donc entièrement consultable.
- **Pocket** : `previous_application` / `next_application` parcourent toutes les applications connues de la machine sélectionnée. La sélection remet à zéro les pages internes et les confirmations tactiles en cours.
- Les listes de commandes côté Master et Pocket respectent désormais `uiHidden`, en cohérence avec les cartes graphiques et les identifiants distants exportés.
- Les boutons graphiques distants sont désactivés si la source est devenue obsolète (`supervision.staleMs`). Une confirmation tactile porte désormais aussi l'identité réseau de la source, en plus de la machine et de l'application.
- **Recette finale** : faire publier au moins deux applications sur la même machine, parcourir les deux depuis Master et Pocket, vérifier les catégories/graphiques/contrôles et contrôler l'affichage d'une source devenue stale.

## Graphiques SDK — historique unifié et fenêtres temporelles

- **A-01 / A-09** : `lib/sdk_graph_history.lua` centralise l'accumulation d'échantillons distants pour Master et Pocket. Les snapshots ne transmettent que le dernier échantillon : le client reconstruit localement une série limitée à 120 points et à la fenêtre `timeWindow` déclarée par l'application. Les doublons de timestamp actualisent le dernier point ; les échantillons reçus hors ordre n'introduisent pas de retour en arrière dans la courbe.
- **A-10** : le renderer CC:Graphics choisit l'échelle automatique à partir des échantillons réellement visibles dans `timeWindow` (en secondes), au lieu de laisser un ancien pic hors écran déformer l'axe des valeurs.
- **Déploiement** : le nouveau module est inclus dans `core.runtime`. Master, Pocket et le runtime doivent provenir de la même révision lors de la mise à jour.
- **Recette finale** : confirmer une courbe dynamique sur Pocket et Master, l'absence de points dupliqués lorsqu'un snapshot répète la dernière mesure, l'évolution correcte de l'axe après sortie d'un pic de la fenêtre et l'absence de régression en changeant d'application ou de machine. La conformité reste à vérifier sous CraftOS.

## Mode texte et moniteurs compacts — stabilisation du renderer (A-09 / A-10)

Les vues déclaratives de Pocket, Master et des applications SDK utilisent maintenant aussi les widgets `data`, `group`, `graph`, `action` et `machine-row` en mode texte. Auparavant, le renderer texte n'interprétait pas `widgets` ni `exportGroups`, ce qui pouvait produire des écrans vides lorsque CC:Graphics était absent ou désactivé.

- Les sections `DATA`, `GRAPHS` et `CONTROLS` des applications distantes apparaissent dans les pages texte, regroupées par catégorie et paginées suivant la hauteur disponible.
- Les commandes tactiles passent par les **mêmes identifiants SDK** que le renderer graphique (`display.control.<ID>` et `display.control.remote.<ID>`) ; le runtime conserve la confirmation et le contrôle de source.
- Les écrans texte affichent la liste des machines, permettent de sélectionner une entrée et proposent une navigation entre vues par les flèches de la première ligne.
- La sélection d'application distante se fait via les flèches de source : deuxième ligne sur grand moniteur, avant-dernière ligne sur les moniteurs compacts. Sur ces petits écrans, la navigation de source a priorité sur le bouton permettant de passer en mode graphique.
- La pagination compacte ne réserve pas une page entière à un seul en-tête de catégorie et ne dessine pas de flèches PREV/NEXT inactives.
- Master et Pocket remettent `app.displayPage` à 1 lors d'un changement explicite de source ; les pages internes de métriques, graphes et contrôles sont également réinitialisées.
- La vue de résumé texte existante (`textSummary`) est conservée pour les applications qui l'utilisent ; le résultat de rendu expose correctement la disponibilité éventuelle du basculement graphique.
- Les toasts de confirmation et d'erreur sont également affichés en mode texte. Lorsqu'un toast recouvre la ligne secondaire, ses anciens boutons sont temporairement désactivés afin d'éviter un clic inattendu.

**Recette Minecraft finale** : depuis un moniteur texte et un écran CC:Graphics, parcourir les vues, les applications d'une même machine, les groupes d'exports et plusieurs pages ; vérifier qu'un bouton tactile distant demande sa confirmation, que les actions de navigation ne la demandent pas, qu'une source stale ne montre pas des contrôles actifs et que la présentation reste utilisable sur un moniteur compact. Aucun test en jeu réalisé pour cette passe.

## Stabilisation de l'affichage et des interactions — passe suivante

Cette passe privilégie la cohérence des vues plutôt que de nouveaux mécanismes de protection matérielle :

- **Descripteur unique par rendu** : `app:draw()` ne résout plus deux fois les mesures/contrôles lorsque CC:Graphics échoue et que le SDK retombe sur le mode texte. Un même rafraîchissement utilise le même jeu de données.
- **Widgets locaux** : les `toggle` déclaratifs fonctionnent désormais en mode texte normal et compact, avec indication ON/OFF et commande ON/OFF choisie à partir de l'état exporté. Les bannières sont également lisibles sur les petits écrans.
- **Résumé texte explicite** : `display.viewMode="views"` ne détourne plus automatiquement les applications vers `textSummary`. La configuration `display.textSummary=true` active ce comportement lorsque souhaité. SteamPlant conserve explicitement son écran de statut texte actuel via `apps/steamplant/config.lua`. Une autre application qui utilise `textSummary` doit ajouter ce réglage si elle souhaite conserver ce rendu prioritaire.
- **Commandes locales** : un contrôle tactile ordinaire (`confirm=false`) s'exécute en une pression ; `confirm=true` garde la confirmation en deux pressions, sauf lorsque `display.confirmControls=false` la désactive explicitement. Les commandes distantes conservent leur confirmation actuelle, indépendante de cette règle locale.
- **Navigation** : changer de vue, de page ou de catégorie annule une confirmation locale en cours. La sélection directe d'une machine dans Master remet aussi le numéro de page du renderer à 1.
- **Disponibilité** : les boutons de commande du renderer texte suivent `monitor=true` et `enabled` comme le runtime ; un contrôle non tactile apparaît inactif au lieu de suggérer qu'il est cliquable.

**Vérification finale Minecraft** : alterner les backends graphiques/texte sur Master et Pocket, naviguer puis tester les toggles et les commandes `confirm=false/true`, ainsi que la vue de statut texte SteamPlant. Aucune recette CraftOS en jeu n'a encore été exécutée.

## Réception des applications cohébergées — réseau SDK

Les snapshots et événements conservent toujours une identité **machine**, mais plusieurs applications SDK peuvent fonctionner sur le même ordinateur CraftOS.

- **Snapshots** : le récepteur ignore uniquement les annonces de sa propre application (`machine + module`) au lieu d'ignorer tous les modules de sa machine.
- **Événements** : les nouveaux messages `attacc.sdk.event.v1` incluent un champ `module` donnant l'application émettrice. Les événements d'une application sœur ne sont plus écartés simplement parce que leur `origin` est celui de la même CC. Les anciens événements dépourvus de `module` gardent le filtrage de boucle précédent.
- **Limite** : cette correction concerne la **réception de messages effectivement livrés**. Elle n'ajoute pas de bus local ni de renvoi de paquets vers la même interface modem : la cohabitation sur un seul ordinateur reste à tester dans Minecraft selon le chemin réseau réel.
- **Recette finale** : avec plusieurs applications sur une machine (si les snapshots/événements arrivent au modem), vérifier que Master et Pocket peuvent afficher chacune d'elles, sans se dupliquer eux-mêmes.

## Mise à jour des packages sans téléchargements redondants — A-18

Le gestionnaire `pkgctl update` construit désormais **une seule liste ordonnée de dépendances** pour tous les packages racines installés explicitement. Chaque package (dont `runtime.package-manager`, `core.runtime`, `module.display`) est téléchargé et installé une seule fois durant cette commande, même si plusieurs applications en dépendent. Les indicateurs `explicit` et l'ordre des dépendances sont conservés.

Cette optimisation n'ajoute ni daemon, ni GitHub Actions, ni nouveau protocole. `pkgctl install <package>` et `pkgctl update <package>` conservent leur interface. Une erreur pendant une mise à jour multi-package peut toujours laisser les packages déjà mis à jour et les autres encore anciens : il ne s'agit pas d'une transaction globale.

Lors de la recette Minecraft finale, vérifier `pkgctl source test`, `pkgctl status`, puis le résultat de `pkgctl update` pour chaque type de CC. Les prérequis `core.runtime` et `module.display` doivent être installés à la même révision que Pocket/Master pour ce chantier. **A-19** reste une limitation acceptée : sans application démarrée, une CC ne fait pas tourner de service réseau AttaCC et ne peut donc pas recevoir les commandes distantes.

## Migration des autorisations système — A-12 (P1)

`/etc/attacc/system.lua` est **la seule autorité** pour les actions d'administration système. Les permissions configurées dans l'ancienne configuration de SteamPlant ne suffisent plus.

1. **Avant mise à jour :** sauvegarder `/etc/attacc/`, les fichiers de l'application, et relever les permissions administratives réellement nécessaires.
2. **Après mise à jour :** lancer `systemctl status` et vérifier la présence de `/etc/attacc/system.lua`.
3. **Configurer explicitement :** `systemctl config`, rubrique `admin`. `admin.enabled` et chacune des actions `reboot`, `package_update`, `package_configure` restent à `false` tant qu'elles ne sont pas activées.
4. **Vérifier :** `systemctl status`, puis `authctl` côté machine cible pour l'autorisation des machines appelantes. Les deux politiques sont indépendantes.
5. **Tester :** vérifier le refus par défaut d'une action non autorisée. Un timeout sur le client n'est **pas** une preuve que l'opération a été exécutée.
6. **Ne pas recopier les autorisations historiques automatiquement.** Une migration doit maintenir la politique de refus par défaut.

Exemple indicatif de configuration (adapter aux besoins réels, ne pas activer en production sans vérification) :

```lua
return {
  admin = {
    enabled = false,
    actions = {
      reboot = false,
      package_update = false,
      package_configure = false
    }
  }
}
```

**Attention** : le service réseau fonctionne quand une application SDK est démarrée ; installer le runtime seul ne rend pas la machine administrable à distance.

## Recette bloquante avant merge

- [ ] A-01 — Export local et distant des catégories, labels, valeurs et métadonnées identiques.
- [ ] A-09 — Identifiants de contrôle explicites, sans index `remote_export_N` dépendant de la pagination.
- [ ] A-16 — Toggle local, toggle distant, double appui, deux clients simultanés, transition automatique, état matériel non encore confirmé.
- [ ] A-17 — Vérifier et documenter chaque précondition de `running_topology` et `all_cut` sur le montage réel.
- [ ] A-18 — Tester Pocket/Master/runtime/applications à versions mixtes et déploiement de packages.
- [ ] Auth — ACK forgé, révocation, rejeu, mauvaise signature, timeout.
- [ ] Déploiement — installation vierge, mise à jour, préservation des paramètres, procédure de retour arrière.
- [ ] Réseau — machine détectée sans application, arrêt d'application, disparition, retour, snapshots hors ordre.
- [ ] Écran — 1/2 rangées, pagination, clics, toasts pendant les confirmations.

Les vérifications et tests en jeu seront effectués ensemble une fois les corrections terminées. Aucune recette physique n'est encore validée.
