# AttaCC — Installation, mise à jour et dépannage

Ce guide couvre le flux actuel de la V0.34 (CC:Tweaked + Docker Web). Les installations actives utilisent souvent un Repository Web **persistant**, distinct du code Git local du conteneur.

## 1. Mettre à jour le Docker Web

Sur l'hôte Docker, choisissez la branche validée pour vos tests :

```sh
cd ~/steamplant-cc
git fetch origin
git switch feature/v0.34-developer-sdk
git pull --ff-only origin feature/v0.34-developer-sdk
cd web
docker compose up -d --build --force-recreate
docker compose ps
docker compose logs --tail=100
```

Le changement de branche et le rebuild ne synchronisent **pas nécessairement** `/data/managed-repository` (le Repository géré). L'import Git du panneau Repository peut remplacer les packages customs déjà présents : sauvegardez `web/data` et les ZIP customs avant l'import.

Ne jamais utiliser `docker compose down -v` pour une simple mise à jour.

## 2. Vérifier la source réellement servie

Depuis un terminal sur l'hôte Docker (adapter l'adresse) :

```sh
curl -fsS http://HOST:8080/repo/packages/manifest.lua | head
curl -fsS http://HOST:8080/repo/pkgctl.lua | head
curl -fsS http://HOST:8080/repo/core/logctl.lua | head
```

Cela permet de confirmer la version **réellement servie** aux CC et pas seulement les fichiers de Git. Dans la WebUI, configurez la branche cible du dépôt et effectuez l'import Git seulement après sauvegarde des packages customs.

## 3. Première installation sur une CC de test

```lua
wget http://HOST:8080/repo/install.lua install
install
pkgctl source show
pkgctl source test
pkgctl status
```

`install` retélécharge son propre `pkgctl.lua` depuis la source configurée. Modifier le fichier seulement sur la CC ne corrige donc pas un Repository Web obsolète.

## 4. Mettre à jour une CC existante

```lua
pkgctl source test
pkgctl show core.runtime
pkgctl update core.runtime
reboot
logctl status
logctl errors
logctl tail 30
```

Après changement majeur du gestionnaire, récupérer d'abord `pkgctl.lua` depuis le Repository, avec une copie de sauvegarde :

```lua
wget http://HOST:8080/repo/pkgctl.lua pkgctl-new.lua
cp pkgctl.lua pkgctl-old.lua
mv pkgctl-new.lua pkgctl.lua
```

Effectuez les opérations de bascule de fichiers uniquement hors de toute commande `pkgctl` active.

## 5. Cas courants

| Symptôme | Vérifications |
|---|---|
| `pkgctl source test` échoue | URL `/repo`, serveur Docker accessible, HTTP autorisé dans CC:Tweaked |
| `pkgctl` refuse un fichier et Git contient déjà la correction | Comparer le fichier Git avec `curl .../repo/pkgctl.lua` ; le Repository persistant peut être en retard |
| Module absent dans `require` | Vérifier le chemin `dest` du manifeste et le nom chargé dans Lua |
| Preset inconnu au boot | Lire `/etc/preset`, consulter `logctl errors` et `logctl status` |
| Application principale manquante | Vérifier `workstation.lua` (ou le nom affiché) ; restaurer son package |
| Un import Git remplace un custom | Restaurer depuis la sauvegarde avant de réimporter le package |
| Absence de couleurs | Les terminaux CraftOS monochromes affichent les statuts sans couleur |

## 6. Presets personnalisés

Dans **Repository → Code & Import → Custom boot preset**, le preset référence une application installable et le chemin de son programme de boot. Sur une CC de test :

```lua
pkgctl install preset.example
pkgctl activate preset.example
reboot
```

`activate` remplace le preset actif de cet ordinateur ; les autres packages installés ne sont pas supprimés automatiquement. Ne pas basculer le Master ou la SteamPlant principale avant d'avoir testé le preset.

## 7. Informations à recueillir lors d'un bug

- Version annoncée par `pkgctl source test` et version dans `/repo/packages/manifest.lua`
- Nom de la branche de Git et éventuel import Git du Repository géré
- Copie de `logctl errors` et `logctl status`
- Nom de la CC (normal, Advanced, Pocket), preset actif, périphériques branchés
- Commande déclenchante et message complet, avec numéro de ligne

**Les journaux d'une CC ne constituent pas une authentification réseau.** Ne publiez pas de tokens ou d'identifiants dans un rapport de bug.
