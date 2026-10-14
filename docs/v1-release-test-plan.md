# AttaCC V1 — Recette de validation avant publication

**Branche de test :** `release/v1.0.0-prep`. **Ne pas déployer sur le Master/SteamPlant de production.** À cette étape le manifeste annonce encore `0.34.0-dev` ; `1.0.0` sera fixé après validation.

## Préconditions

- Une sauvegarde du dépôt Web persistant et des ZIP personnalisés.
- Deux ordinateurs **de test** en Minecraft : un Advanced Computer (Workstation) et un Computer normal (Workstation ou autre preset compatible).
- Accès réseau depuis les CC vers l'URL HTTP du Docker (exemple : `http://192.168.1.202:8080/repo`).
- Valeurs personnalisées et **différentes** de `MACHINE_TOKEN` et `ADMIN_TOKEN` dans `web/.env`. Ne pas afficher ces valeurs.

## 1. Sauvegarde et build Docker

```bash
cd ~/steamplant-cc
git fetch origin
git switch release/v1.0.0-prep || git switch --track origin/release/v1.0.0-prep
git pull --ff-only origin release/v1.0.0-prep

cd web
test -f .env || { echo "web/.env manquant"; exit 1; }
mkdir -p ../backups
tar -czf "../backups/attacc-web-$(date +%Y%m%d-%H%M).tar.gz" data
docker compose config --quiet
docker compose up -d --build --force-recreate
docker compose ps
docker compose logs --tail=80
```

Ne pas utiliser `docker compose down -v`.

Le backend **refuse volontairement de démarrer** si les tokens sont absents, identiques ou laissent les valeurs `change-me-...`. Conserver le `MACHINE_TOKEN` existant s'il est déjà personnalisé, afin de ne pas déconnecter le Master.

## 2. Vérifier le Repository réellement servi

Le Docker charge son code depuis Git, mais le Repository HTTP peut servir `web/data/managed-repository` (qui est persistant).

```bash
curl -fsS http://192.168.1.202:8080/repo/packages/manifest.lua | head -n 5
curl -fsS http://192.168.1.202:8080/repo/pkgctl.lua | head -n 5
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.1.202:8080/repo/.git/config
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.1.202:8080/repo/.env
```

Les deux dernières requêtes doivent être bloquées (400 ou 404). Les premières doivent retourner les fichiers Lua.

Si le manifeste servi n'est **pas** celui de la branche de test, un import Git depuis l'administration du Repository peut le mettre à jour, **mais cet import est susceptible d'écraser les packages customs**. Sur l'instance courante, conserver au préalable les ZIP customs et une sauvegarde vérifiée. Idéalement utiliser une instance Web de test avec un dossier `data` dédié plutôt que d'écraser le dépôt actif.

## 3. Fresh install sur Advanced Computer

Sur une Advanced Computer vierge :

```lua
wget http://192.168.1.202:8080/repo/install.lua install
install
```

Choisir **Workstation**. Après installation/redémarrage :

```lua
pkgctl source test
pkgctl status
logctl status
logctl errors
```

**Attendu :** source joignable, packages présents, statut `startup: ready`, pas d'erreur inexpliquée. L'affichage de l'app Workstation doit être normal.

## 4. Fresh install sur Computer normal

Répéter les commandes d'installation sur une CC **normale** et sélectionner Workstation ou un autre preset compatible avec ses périphériques. Au démarrage, `startup.lua` exécute l'app en terminal principal (pas de multishell). Vérifier `pkgctl status`, `logctl status` et la disponibilité du terminal / programme.

Ne pas réclamer des écrans, modems ou capteurs absents sans vérifier les exigences propres au preset choisi.

## 5. App Store : créer, mettre à jour, supprimer

Sur l'instance Web **de test** :

1. Importer `app.review-example` version `1.0.0` depuis un ZIP contenant un fichier Lua minimal.
2. Sur l'Advanced Computer : `pkgctl install app.review-example`, puis `pkgctl show app.review-example`.
3. Publier une version `1.1.0` et vérifier `pkgctl status` puis `pkgctl update app.review-example`.
4. Tester le programme et la mise à jour de ses fichiers.
5. Supprimer le package dans la WebUI lorsque plus aucun autre package n'en dépend ; vérifier le catalogue.
6. Ne pas lancer `pkgctl prune` sur une CC qui héberge des packages utiles au test sans vérifier les racines explicites.

L'exemple `examples/sdk-hello` peut servir de source pour le ZIP.

## 6. Preset personnalisé

Créer `preset.review-example` dans l'éditeur Web, dépendant de `app.review-example`, avec un `program` correspondant au `dest` réellement installé.

Sur une CC spare :

```lua
pkgctl install preset.review-example
pkgctl activate preset.review-example
reboot
```

**Attendu :** l'application personnalisée démarre. Ne pas faire ce test sur le Master ni sur la SteamPlant active. Sauvegarder d'abord `/etc/preset` si l'ordinateur n'est pas vierge.

## 7. Vérifier WebBridge et l'administration

Sur le Web : confirmer la présence du Master, les événements, la télémétrie et les opérations d'administration usuelles avec le vrai token. Une requête sur une route d'administration sans token doit renvoyer 401.

La validation des tokens n'exige pas de changer le token d'une installation déjà configurée.

## 8. Test de retour arrière

Restaurer le Repository Web uniquement depuis une **copie de test** de `data`. Confirmer qu'une version sauvegardée retrouve son catalogue et ses packages customs. Ne pas remplacer directement le dossier `web/data` de production pendant que le conteneur fonctionne.

## 9. Critères pour publication

- [ ] Docker build et logs sans erreur
- [ ] Les fichiers HTTP servis correspondent à la branche attendue
- [ ] Chemins cachés `/repo/.git` et `/repo/.env` bloqués
- [ ] Installations Advanced et normale fonctionnelles
- [ ] `pkgctl` / `logctl` fonctionnels
- [ ] Import, mise à jour et suppression custom validés
- [ ] Preset personnalisé testé au boot
- [ ] Master/WebBridge et administration inchangés
- [ ] Sauvegarde et retour arrière testés sur une copie

Une fois validé : fixer les versions à `1.0.0`, publier les notes de release, merger vers `dev` puis `main` après accord, et seulement après renommer le dépôt GitHub.

## Restitution des tests

Noter pour chaque cas : résultat OK/KO, type de CC, commande effectuée, message d'erreur exact et capture si utile. Les défauts critiques bloquent la release, les limites Minecraft connues (par exemple absence de transaction anti-crash) restent documentées.
