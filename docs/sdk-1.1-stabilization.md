# AttaCC 1.1 SDK — stabilisation et migration

Document de suivi de l'audit technique du 17 octobre 2026. Branche d'intégration : `feature/v1.1-sdk-unification`.
Ne pas considérer cette branche comme stable avant une recette en jeu.

## Corrections effectuées

- **A-03 (P2)** : `sdk_snapshot.frame()` ajoute `descriptor.exportWarnings.truncated` quand les limites de 64 DATA, 64 GRAPHS, 64 CONTROLS ou 16 VIEWS sont dépassées. La compatibilité des anciennes trames est préservée. Le réseau conserve ses limites : les entrées excédentaires ne sont pas transmises.
- **A-14 (P2)** : `sdk_system_config.load()` rejette les échelles incompatibles avec CC:Tweaked et les décalages tactiles non entiers ou hors limites ; les noms de moniteur contenant des caractères de contrôle sont rejetés.
- **Qualité (P1)** : vérification de syntaxe Lua 5.2 en CI, sans exécuter les scripts CraftOS.

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

La CI syntaxique ne couvre ni les APIs CraftOS ni le comportement réel des machines. Aucune recette physique n'est validée par ce document.
