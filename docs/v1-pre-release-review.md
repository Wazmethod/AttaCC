# AttaCC — Revue pré-V1 et transition de nom

Branche de préparation : `release/v1.0.0-prep` (créée depuis `dev`). **Aucun merge sur main ni renommage GitHub à ce stade.**

## Nommage : règle

**AttaCC** est le nom du projet, du runtime, du Web et du SDK. **SteamPlant** désigne uniquement l'application métier du générateur Minecraft et ses fichiers dédiés (`apps/steamplant`, `steamplant.lua`, `preset.steamplant`, etc.). Ne pas renommer ces éléments, sinon les CC et presets existants ne démarrent plus.

### Modifications effectuées

- `web/frontend/package.json` : ancien nom technique `steamplant-dashboard` remplacé par `attacc-web`.
- `web/backend/package.json` : ancien nom `steamplant-backend` remplacé par `attacc-web-backend`.
- `web/frontend/src/DocsView.jsx` : liens historiques de branches pointant désormais sur `dev`, suppression d'une étiquette de version obsolète.

### Noms volontairement conservés jusqu'au renommage GitHub

- `Wazmethod/steamplant-cc` dans les URLs GitHub, les valeurs `OWNER`/`REPO` du bootstrap et du fallback `pkgctl`, ainsi que dans les guides : ils désignent un **dépôt existant**, pas le produit.
- Références SteamPlant dans l'application proprement dite : elles resteront en place après V1.

**Après le merge V1 sur main**, renommer le dépôt GitHub, puis remplacer les références techniques au slug GitHub par le nouveau slug dans un commit séparé et vérifier `wget`, `install`, `pkgctl source github`, la WebUI et les imports Git. GitHub redirige généralement les anciennes URLs de dépôt, mais ne pas s'en remettre uniquement à cette redirection pour la publication stable.

## Revue technique initiale — points à vérifier avant V1

| Priorité | Sujet | Observation fondée sur les sources | Validation attendue |
|---|---|---|---|
| Haute | Identité du produit | Deux noms npm historiques trouvés et corrigés ; les URLs GitHub doivent attendre le renommage du dépôt. | Construire le frontend et démarrer le backend Docker sur la branche de préparation. |
| Haute | Authentification Web | `web/backend/server.js` possède encore un fallback `change-me-admin-token` ; les routes d'administration appellent `requireAdmin`. | Vérifier la gestion des tokens à l'installation et que le token par défaut ne permet jamais d'administrer une instance exposée. |
| Haute | Dépôt Web persistant | Le Web peut servir un `/data/managed-repository` distinct du checkout Docker : le redéploiement ne garantit pas la mise à jour du catalogue. | Sauvegarde, import Git test, conservation/restauration des packages customs, vérification des fichiers servis par `/repo`. |
| Haute | Installation / mise à jour CraftOS | `pkgctl` télécharge avant d'écrire et tente une restauration mémoire, mais une interruption en cours d'écriture ne dispose pas d'une transaction persistante. | Installer depuis zéro, mettre à jour, interrompre un téléchargement, vérifier le démarrage après redémarrage. |
| Moyenne | Presets | Les presets natifs et customs doivent continuer à fonctionner, y compris après une mise à jour. | Tester SteamPlant, Master, Workstation, Dashboard et un preset custom sur des CC de test. |
| Moyenne | Journalisation | `logctl status/errors/tail` et les erreurs de preset/programme ont déjà été testés en jeu en V0.33. | Confirmer une fois après le packaging V1. |
| Moyenne | Documentation | Documentation SDK V0.34 intégrée au DOCS Web ; certains guides historiques indiquent leurs branches d'origine. | Vérifier les liens internes et garder un titre de version correspondant à la release. |
| Moyenne | Package manager / App Store | Les opérations ZIP, versions et mise à jour custom ont été testées pendant le développement mais pas via une recette de release homogène. | Créer, installer, mettre à jour et supprimer un package custom depuis une instance de test. |

## Recette de publication proposée

1. Revue de code ciblée sécurité et robustesse (Web admin, installation CraftOS, Repository import).
2. Tests de build Docker et test manuel sur un monde Minecraft de test.
3. Correction des anomalies confirmées uniquement ; éviter de nouvelles grosses fonctionnalités avant la V1.
4. Gel de la version et publication des instructions de migration depuis V0.34.
5. PR `release/v1.0.0-prep` → `dev`, puis validation explicite du passage sur `main`.
6. Après publication V1 sur `main`, renommer le dépôt GitHub et traiter les liens techniques séparément.

Cette revue est **initiale et statique** ; elle ne remplace pas des tests Docker et CraftOS complets.
