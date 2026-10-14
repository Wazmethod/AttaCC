# AttaCC V1 — Revue Package Manager / Repository

Branche : `release/v1.0.0-prep`. Cette revue est issue de la lecture de `pkgctl.lua` et `web/backend/server.js` ; **aucun test en jeu/Docker n'est revendiqué ici**.

## Constats

| Priorité | Composant | Constat confirmé dans les sources | Décision proposée |
|---|---|---|---|
| Haute | `pkgctl install/update` | Les fichiers sont pré-téléchargés avant écriture pour **chaque package** ; le remplacement et l'écriture de la DB ne sont pas atomiques en cas d'arrêt forcé. La restauration reste en mémoire. | Accepter explicitement cette limite Minecraft pour V1 ; tester interruption de téléchargement et documenter la récupération via réinstallation/backup. Ne pas promettre de rollback après crash. |
| Haute | Web Repository | `/data/managed-repository` reste autonome du code Git monté sous `/repo`. Un redéploiement du conteneur n'actualise pas automatiquement les packages servis. | Exiger vérification HTTP du manifeste servi après chaque déploiement ; sauvegarder `web/data` et ZIP customs avant import Git. |
| Moyenne | Custom registry | Le catalogue utilise `customPackageNames()` (incluant les packages hérités), mais l'API de suppression utilise uniquement `/data/repository-custom-packages.json`. Un package ancien peut donc être marqué custom et refusé à la suppression. | Maintenir ce comportement connu pour V1 (déjà identifié et délibérément non modifié à la demande) ; le documenter et utiliser une correction ponctuelle du registre en cas de besoin. |
| Moyenne | Publication custom | Les imports modernes valident dépendances, fichiers, syntaxe Lua et construisent un dépôt temporaire avant de l'activer ; manifeste et registre custom sont enregistrés en deux étapes distinctes. | Tester après arrêt/redémarrage Docker, conserver backup. |
| Moyenne | Mises à jour custom | La suppression d'une ancienne définition de package s'appuie sur un marqueur de texte `\n        },` plutôt que sur une AST Lua réécrivable. | Ne pas éditer à la main la structure des déclarations générées si leur mise à jour Web est prévue ; test create/update/delete dans un Repository de test. |
| Faible | Lecture `/repo` | La protection des chemins cachés existe ; un contrôle de caractère NUL interprétait auparavant la séquence littérale `\\0` au lieu du NUL. | Corrigé dans la branche V1 : rejet du caractère NUL réel. |

## Scénarios de validation avant main

1. Dans un dépôt Web **de test**, créer `app.review-example` via ZIP avec un helper et une version `1.0.0`.
2. Installer sur une Advanced Computer dédiée : `pkgctl source test`, `pkgctl install app.review-example`, `pkgctl show app.review-example`.
3. Mettre à jour la version vers `1.1.0`, ajouter un fichier et retirer un fichier obsolète ; vérifier que le programme démarre.
4. Couper la connexion HTTP pendant le téléchargement d'un update : les anciens fichiers doivent rester fonctionnels si aucun remplacement n'a débuté.
5. Supprimer le package custom après suppression des éventuelles dépendances qui le référencent ; vérifier le catalogue Web et le manifeste.
6. Tester sur copie de `web/data` la restauration du Repository et l'import Git, sans toucher au dépôt contenant les vrais packages customs.
7. Vérifier le fonctionnement des presets natifs et du preset custom après redémarrage.

## Limites de release

Ne pas renommer les clés de packages, `startup.lua`, les destinations de fichiers ni les presets natifs pendant cette revue de nommage. La V1 vise une version **fonctionnelle et facile à dépanner dans Minecraft**, pas une infrastructure transactionnelle.

Les noms des services Docker et les URLs du dépôt historique restent stables jusqu'au renommage GitHub post-publication.
