# Audit technique — AttaCC Native Runtime

Date : 2026-10-14. Référence : `refactor/native-runtime-v1`.

**Méthode** : inspection statique des points d'entrée, du manifeste, du runtime, des outils Storage, du Pocket, du backend Web et de la documentation. Aucune instance Minecraft/CC ni conteneur utilisateur n'est accessible depuis cette revue ; les tests fonctionnels restent à exécuter. Les constats ci-dessous indiquent ce que le code prouve, et non un fonctionnement constaté dans le jeu.

## Constats confirmés par lecture du code

| ID | Niveau | Fichier / comportement | Conséquence et recommandation |
|---|---|---|---|
| SEC-01 | **Critique avant exposition publique** | `web/backend/server.js` substitue `change-me-machine-token` et `change-me-admin-token` quand les variables sont absentes ; `web/.env.example` propose ces valeurs. | Utiliser deux secrets forts, différents ; renforcer ultérieurement le démarrage pour refuser les valeurs d'exemple. Tester l'auth sans token. |
| SEC-02 | **À décider selon périmètre Web** | `/api/status`, `/api/networks`, `/api/events` et `/ws/browser` exposent des données sans authentification applicative, alors que les routes d'administration exigent un token. | Si l'interface ne doit pas être publique, ajouter contrôle d'accès côté proxy ou dans l'application. |
| SEC-03 | **Risque logique réseau** | `modules/storage/network_store.lua` autorise les opérations définies dans le protocole quand la cible et le réseau correspondent ; aucune authentification forte du modem ne figure dans ce module. | Un autre CC du même réseau logique pourrait émettre des requêtes Storage. Prévoir autorisation d'origine et protection des commandes mutantes si adversaires possibles. |
| OPS-01 | **Risque migration** | `storagehostctl migrate` copie et vérifie le fichier avant de sélectionner le nouveau backend, mais n'interdit pas simultanément les écritures clients. | Arrêter les écritures pour toute migration ; tester sur un disque vierge. Un mode maintenance serveur serait préférable. |
| OPS-02 | **Risque écriture** | Les écritures du backend reposent sur un fichier JSON et un remplacement `.new` ; aucune transaction inter-processus globale n'est apparente. | Tester coupures, limites de taille, sauvegardes et appels simultanés. |
| OPS-03 | **Risque déploiement** | `core/startup.lua` lance le serveur Storage si `storagehost.lua` est installé, indépendamment de la présence d'un preset serveur. | Contrôler explicitement les racines installées et l'usage de `pkgctl prune`. |
| GUI-01 | **Limite confirmée** | Le Pocket active CC:Graphics sur le terminal principal : ce n'est pas une surface textuelle distincte. | Le splash réseau est visible avant le lancement graphique ; il n'est pas garanti visible ensuite en parallèle. |
| OPS-04 | **Risque disponibilité** | Mise à jour de paquet et opérations de configuration exécutées en CraftOS peuvent dépendre de l'environnement shell/multishell. | Tester systématiquement lancer en CLI, depuis un bouton et depuis Web ; vérifier les erreurs et le redémarrage. |

## Comportements récemment corrigés, à tester

- Découverte Storage : timer borné à cinq secondes.
- Sélection du Storage : `storagectl use` est obligatoire, y compris pour les appels locaux ; `ping` ne doit pas interroger un hôte quelconque.
- Les réponses Storage côté client sont filtrées par la clé de l'hôte sélectionné.
- `profilectl storage-sync` n'exige plus une seconde saisie de l'hôte.
- Boutons de l'onglet Storage : invocation `shell.openTab`.
- Bouton Network Labels WebBridge : passe l'argument `configure`.
- Pocket : titres/sous-pages, événements HOSTNAME/CODE/INFO, splash AttaCC et bascule `T`.

## Manques de validation

La présente revue ne constitue pas une preuve de compilation ou d'exécution des 100 fichiers du dépôt. À compléter avec : analyse syntaxique Lua compatible CraftOS, build Vite, tests unitaires sur protocole/Storage/profils, simulations de coupure, et la recette end-to-end. Aucun feu vert de production ne doit être déduit du seul audit statique.

## Plan d'amélioration priorisé

1. **P0** : secrets Web forts, accès à la télémétrie selon la politique voulue, test des autorisations d'actions et reboot.
2. **P0** : recette Storage sans destination puis avec destination exacte ; sauvegarde et restauration validées.
3. **P1** : maintenance Storage bloquant les écritures pendant migration et contrôles post-migration.
4. **P1** : intégration continue (analyse Lua, build frontend, lint, validation du manifeste).
5. **P2** : tests automatisés d'UI Pocket/Master, télémétrie et reconnexion WebBridge.

Document de référence : [validation-infrastructure.md](validation-infrastructure.md).
