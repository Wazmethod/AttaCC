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
