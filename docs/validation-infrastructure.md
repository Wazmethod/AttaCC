# AttaCC — validation intégrale de l'infrastructure

**Statut : NON EXÉCUTÉ EN JEU** (plan de recette issu de l'inspection de `refactor/native-runtime-v1`, 14 octobre 2026).

Inscrire pour chaque cas : date/heure, rôle, Computer ID, hostname, réseau, résultat **PASS/FAIL**, capture ou journal, et commit GitHub installé. Ne pas effectuer les tests destructifs sur des données de production sans sauvegarde.

## Prérequis et inventaire

Créer une feuille de résultats pour les nœuds : SteamPlant, Master, Storage host (éventuellement même CC), Workstation, Pocket, Dashboard et WebBridge. Noter pour chaque nœud : clé logique, Computer ID, réseau, version/preset, modem, périphériques et chemin réel du Store. Séparer les environnements test et production.

### Phase A — intégrité et démarrage (A01–A07)

| ID | Test | Commande/action | Attendu |
|---|---|---|---|
| A01 | Paquets installés | `pkgctl status` sur chaque rôle | Aucun `MISSING`, dépendances complètes |
| A02 | Preset et identité | `cat /etc/preset`, `machinectl status` | Rôle et identité uniques et cohérents |
| A03 | Profil complet | `profilectl show` | Identité, profil, Storage et configuration effective lisibles |
| A04 | Reboot | `reboot` sur chaque machine, une par une | Chaque application et service prévu redémarre |
| A05 | Service optionnel | Inspecter onglets Master/Storage/WebBridge | Aucun processus serveur inattendu |
| A06 | Modules manquants | Vérifier `ls /lib` et `pkgctl status` | Aucune erreur `require` à l'exécution |
| A07 | Shell/help | Appeler `pkgctl`, `storagectl`, `profilectl`, `machinectl`, `ioctl` sans paramètres | Aide lisible et pas d'erreur |

### Phase B — réseau et découverte (B01–B07)

| ID | Test | Action | Attendu |
|---|---|---|---|
| B01 | Matériel réseau | Inspecter les modems sans fil sur tous les nœuds | Modems opérationnels |
| B02 | Découverte des nœuds | Page NETWORK Master/Pocket | Toutes les machines attendues, sans collision de clés |
| B03 | Découverte Storage | `storagectl hosts` depuis Workstation et Pocket | Fin en ~5 secondes ; clé exacte de l'hôte |
| B04 | Réseau incorrect | Utiliser une machine de test d'un autre réseau logique | Aucun mélange inattendu d'annonces |
| B05 | Déconnexion | Éteindre temporairement un nœud non critique | Il devient indisponible après expiration |
| B06 | Retour réseau | Redémarrer le nœud de test | Retour automatique, statut cohérent |
| B07 | Conflit d'identité | **Seulement en labo**, simuler une clé dupliquée | Alerte de conflit sans reboot intempestif |

### Phase C — Storage / synchronisation (C01–C12)

| ID | Test | Action | Attendu |
|---|---|---|---|
| C01 | Aucun hôte sélectionné | Sur client de test vierge, `storagectl ping` | Refus explicite, aucune découverte implicite |
| C02 | Affichage cible | `storagectl target` | Clé et namespace cohérents |
| C03 | Sélection | `storagectl use <clé-hôte> attacc.config` | Cible enregistrée |
| C04 | Ping ciblé | `storagectl ping` | Réponse du seul hôte configuré |
| C05 | Cible invalide | Choisir temporairement une fausse clé, puis `ping` | Timeout clair, aucune réponse d'un autre serveur |
| C06 | Test de données | `storagectl set attacc.audit test-01 ok` puis `get` | `ok` restitué |
| C07 | Listage | `storagectl list attacc.audit`, `storagectl tree` | Clé visible |
| C08 | Suppression | `storagectl delete attacc.audit test-01` | Clé absente après suppression |
| C09 | Sync initiale | `profilectl storage-sync`, `profilectl push` | Sauvegarde distante confirmée |
| C10 | Lecture distante | `profilectl machines` ; `profilectl pull` sur machine test | Configuration restaurée ; comparer `profilectl show` |
| C11 | Hôte en panne | Couper temporairement l'hôte dans un environnement de test | Timeout, aucune substitution silencieuse |
| C12 | Accès local explicite | Sur hôte, sélectionner sa clé puis `storagectl ping` ; changer la cible pour une fausse clé | Accès local uniquement avec clé exacte |

**Avant de faire C05**, noter et restaurer la clé réelle via `storagectl use`. **Avant C10**, sauvegarder les trois fichiers `/etc/` sur la machine de test.

### Phase D — backend, sauvegarde et migration (D01–D06)

| ID | Test | Action | Attendu |
|---|---|---|---|
| D01 | Santé serveur | `storagehostctl status` | Backend disponible, chemin et compteurs cohérents |
| D02 | Boutons d'onglet | Status / Tree / Backup / Config / Migrate | Ouverture de l'outil correct, paramètres corrects |
| D03 | Sauvegarde | `storagehostctl backup` | Copie vérifiée, source inchangée |
| D04 | Disque absent | **Labo uniquement**, retirer un disque de test | Dégradation visible, pas de corruption silencieuse |
| D05 | Migration | **Labo uniquement**, `storagehostctl migrate drive` avec disque vierge | Copie vérifiée, source conservée, redémarrage puis lecture identique |
| D06 | Refus écrasement | **Labo uniquement**, destination avec base préexistante | Refus de la migration et aucune perte de données |

### Phase E — SteamPlant et contrôle (E01–E06)

| ID | Test | Action | Attendu |
|---|---|---|---|
| E01 | Télémétrie | Lire état, eau, chaleur, RPM | Données cohérentes, rafraîchissement Master/Web/Pocket |
| E02 | Catégories | DATA / GRAPHS / CONTROLS | Ordre correct, pas de métriques mélangées |
| E03 | Graphes | Laisser tourner plusieurs minutes | Historique se remplit, unités/axes corrects |
| E04 | Commande sûre | Action non destructive autorisée | Accusé réception et changement d'état |
| E05 | Perte ACK | **Labo uniquement**, couper une source de réponse | Délai/erreur visibles, pas de commande infinie |
| E06 | Actions dangereuses | Contrôler la confirmation/autorisation des actions impactantes | Aucune action accidentelle |

### Phase F — Master et Pocket (F01–F10)

| ID | Test | Action | Attendu |
|---|---|---|---|
| F01 | Layout Master | Parcourir toutes ses pages | Aucun chevauchement, navigation intacte |
| F02 | Pocket splash | Redémarrer Pocket | Logo/identité réseau texte brièvement avant l'interface |
| F03 | Pocket texte | `T` pour passer en texte | Affichage texte exploitable |
| F04 | Pocket CC:Graphics | `T` pour revenir en graphique | Affichage et interactions préservés |
| F05 | Pocket sans API graphique | **Labo / autre configuration**, retirer compatibilité | Repli texte, aucun crash |
| F06 | Sous-pages | DATA / GRAPHS / CONTROLS ; flèches | Titres en haut, catégories en bas, index indépendant |
| F07 | Événements | Générer un événement non critique | Colonnes HOSTNAME / CODE / INFO dans les deux rendus |
| F08 | Sélection machine | Changer d'app sur Pocket | Télémétrie et contrôles ciblent la bonne machine |
| F09 | Redémarrage distant | **Machine de test uniquement**, sélectionner puis confirmer | Seule la cible choisie redémarre |
| F10 | Modem perdu | **Labo**, déconnecter réseau | État Offline explicite, interface utilisable |

### Phase G — Web / Docker / droits (G01–G08)

| ID | Test | Action | Attendu |
|---|---|---|---|
| G01 | Docker | `docker compose ps`, `docker compose logs --tail=100` | Conteneur sain, pas de boucle de redémarrage |
| G02 | Santé HTTP | `curl -fsS http://127.0.0.1:8080/api/health` | Réponse HTTP correcte |
| G03 | Bridge | Vérifier lien WebBridge ↔ Web | Bridge connecté, réseaux visibles |
| G04 | Documentation | Parcourir tous les onglets DOCS | Layout desktop/mobile correct, CLI à jour |
| G05 | Refus sans token | Requête POST admin sans authentification | HTTP 401, action non exécutée |
| G06 | Tokens | Vérifier valeurs réelles dans le compose (ne **jamais** publier les tokens) | Tokens non vides, non par défaut et différents |
| G07 | Actions ciblées | Sur machine test, déclencher action Web | Bonne cible, ACK, pas d'exécution libre de shell |
| G08 | Persistance | Redémarrer le conteneur de test | Historique stocké dans le volume conservé |

### Phase H — résilience et régression (H01–H06)

| ID | Test | Action | Attendu |
|---|---|---|---|
| H01 | Update locale | `pkgctl update` sur un nœud de test | Aucun module manquant après reboot |
| H02 | Update Web | Mise à jour pilotée depuis le Web sur nœud test | Onglet, retour de commande et reboot attendus |
| H03 | Journaux | Déclencher un événement informatif | Date UTC lisible, composant et niveau corrects |
| H04 | Durée | 30 à 60 minutes sur tous les rôles | Pas de freeze, fuite mémoire apparente, spam logs |
| H05 | Redémarrage ordonné | Web, Master, Pocket, SteamPlant dans des ordres différents | Reconnexion sans configuration manuelle |
| H06 | Restauration | **Labo uniquement**, restaurer Store et profil depuis sauvegardes | Identités et données retrouvées |

## Critères d'acceptation

**Blocants** : échec de C01/C04/C12 (destination Storage), D03 (backup), E04/E06 (contrôles), F09 (reboot ciblé), G05/G06 (auth) et H01 (update). Les tests destructifs ne doivent pas être exécutés sur le monde principal.

Consigner les résultats par exemple :

```text
Date/heure UTC :
Branche / commit installé :
Nœud / Computer ID / clé :
Test ID :
PASS / FAIL / NON TESTÉ :
Commande ou action :
Résultat observé :
Résultat attendu :
Logs / capture :
Correction ou ticket :
```

Ne considérer la recette globale comme terminée qu'après validation de tous les cas applicables et correction ou acceptation documentée des écarts.
