# Développer des applications, modules et presets AttaCC

> Guide de développement pour le runtime natif **AttaCC 0.34-dev**.
> Les sources de référence du projet sont `apps/`, `modules/`, `core/`, `packages/manifest.lua` et `core/startup.lua`.

## 1. Différence entre app, module et preset

| Élément | Rôle | Exemple |
|---|---|---|
| **App** | Logique métier d'une machine (actions, UI, télémétrie) | `app.steamplant`, `app.master` |
| **Module** | Capacité générique, réutilisable et indépendante de l'app | `module.network`, `module.display` |
| **Preset** | Ensemble installé pour un rôle de machine, avec dépendances | `preset.workstation`, `preset.dashboard` |
| **Core** | Runtime partagé, bus, identité, registres, contrôle, packages | `core.runtime` |

Un preset n'est **pas** une application en soi. Il référence une app et ses dépendances. Depuis la V0.32, l'éditeur Web **Custom boot preset** peut définir son programme de lancement ; `install.lua` découvre les presets personnalisés et `pkgctl activate preset.example` sélectionne le preset après installation.

## 2. Organisation conseillée

```text
apps/
  example/
    main.lua
    config.lua
    controller.lua
    view.lua
modules/
  example_module.lua
packages/
  manifest.lua
docs/
  module-development.md
```

La séparation par responsabilité est importante. Le runtime ne doit pas intégrer la logique particulière d'une machine ; elle appartient à `apps/example/`.

## 3. Importer plusieurs fichiers depuis la WebUI

1. Ouvrir **Repository → Code & Import** et choisir le ZIP du projet.
2. Renseigner **Target directory** (par exemple `apps/example`), puis **Inspect ZIP**.
3. Déclarer le package dans le même écran : Type **Application** ou **Module**, nom `example`, version `1.0.0` et dépendances.
4. Vérifier chaque association source → destination CraftOS. Un fichier `main.lua` peut devenir `example.lua` ; les fichiers chargés via `require("example_helpers")` doivent être placés à un emplacement compatible avec la recherche Lua.
5. Cliquer sur **Validate ZIP & register package** : l'import et la déclaration sont réalisés ensemble.
6. Tester sur une CC avec `pkgctl source test`, `pkgctl show app.example`, puis `pkgctl install app.example`.

Pour un preset personnalisé, utiliser ensuite le panneau **Custom boot preset**. Déclarer une dépendance vers l'app, ainsi qu'un programme de démarrage réellement installé par cette dépendance (par exemple `example.lua`). Puis, sur la CC de test : `pkgctl install preset.example`, `pkgctl activate preset.example`, `reboot`.

Un projet runnable minimal est fourni dans [examples/sdk-hello](../examples/sdk-hello/README.md).

## 4. Exemple minimal de manifeste

```lua
["module.example"] = {
    kind = "module",
    version = "1.0.0",
    description = "Exemple de module réutilisable",
    depends = { "core.runtime" },
    files = {
        { src = "modules/example_module.lua", dest = "lib/example_module.lua" },
    },
},
["app.example"] = {
    kind = "app",
    version = "1.0.0",
    description = "Application de démonstration",
    depends = { "module.network", "module.example" },
    files = {
        { src = "apps/example/main.lua", dest = "example.lua" },
        { src = "apps/example/config.lua", dest = "lib/config.lua" },
        { src = "apps/example/controller.lua", dest = "lib/example_controller.lua" },
        { src = "apps/example/view.lua", dest = "lib/example_view.lua" },
    },
},
["preset.example"] = {
    kind = "preset",
    version = "1.0.0",
    program = "example.lua",
    description = "Machine de démonstration",
    depends = { "app.example" },
    files = {},
},
```

**Attention :** `lib/config.lua` est partagé par le preset installé sur un ordinateur ; ne mélange pas plusieurs configurations d'apps contradictoires sur le même ordinateur sans adapter l'architecture.

## 5. Exemple de module Lua

```lua
-- modules/example_module.lua
local M = {}

function M.describe()
    return { name = "example", status = "ready" }
end

return M
```

Dans l'application qui dépend du module :

```lua
local example = require("lib.example_module")
print(example.describe().status)
```

Les modules réutilisables doivent gérer les périphériques absents, retourner des erreurs compréhensibles et éviter de bloquer le runtime.

## 6. Identité, configuration et périphériques

L'identité persistante est stockée dans `/etc/machine.lua`, les paramètres d'apps dans `/etc/apps.lua` et les liaisons matérielles dans `/etc/io.lua`. `/etc/profile.lua` contient encore des réglages généraux et sert à la compatibilité.

Une application possédant des exigences matérielles peut déclarer des rôles `io.requirements` dans son fichier de configuration, puis passer par le registre I/O : voir `apps/steamplant/config.lua` et `apps/steamplant/io.lua` pour les types attendus et l'exemple complet.

Utilisez `ioctl init`, `ioctl check` et `ioctl hardware` pour tester les périphériques physiques.

## 7. Déploiement des ordinateurs

```lua
wget https://votre-instance/repo/install.lua install
install
pkgctl source show
pkgctl source test
pkgctl list
pkgctl install app.example
```

Le dépôt Web sert l'installateur en injectant l'URL publique configurée dans la WebUI. Si l'ordinateur est déjà installé avec un ancien `pkgctl`, remplacez d'abord le fichier `pkgctl.lua` par la version issue de `/repo/pkgctl.lua`.

L'ajout d'un paquet par `pkgctl install` ne signifie pas automatiquement qu'il est lancé au boot. Pour un preset custom, la commande `pkgctl activate preset.example` règle `/etc/preset` et `/etc/preset_app.lua` pour que le runtime le lance au redémarrage.

## 8. Validation recommandée

- Tous les chemins `src` du manifeste existent dans le dépôt.
- Tous les chemins `dest` sont adaptés au filesystem CraftOS.
- Les dépendances ne forment pas de cycle et sont réellement disponibles.
- Le programme fonctionne avec le type d'ordinateur prévu (normal, Advanced, Pocket).
- Un module facultatif manquant n'empêche pas les autres de démarrer.
- Les erreurs de réseau et de périphériques sont gérées.
- Le redémarrage préserve la configuration locale et l'identité.
- `pkgctl update` n'efface pas les données de `/etc`.
- Un package de test peut être installé depuis AttaCC Web sans accès GitHub.

## 9. Sécurité, versions et évolutions

Le dépôt Web peut être lu par les CC afin de télécharger les packages. Les opérations d'administration requièrent le token Web. Ne publiez jamais de secrets dans le dépôt.

L'import Web des packages valide notamment les chemins de ZIP, les associations de fichiers, les dépendances déclarées et la syntaxe Lua ; il ne garantit pas que le programme fonctionne avec tous les périphériques Minecraft. Les versions de package (`1.0.0`, `1.1.0`…) sont distinctes de celle du runtime. `pkgctl update` télécharge les fichiers avant de les remplacer et tente de restaurer les précédents si une écriture échoue, mais il ne s'agit pas d'un moteur de transactions résistant à un arrêt brutal du jeu.

Pour diagnostiquer une app, utiliser `require("lib.runtime").log("mon-app", "info", "message")` et consulter `logctl tail`, `logctl errors` et `logctl status`. Les journaux sont conservés localement avec une rotation à 64 Kio.

## 10. Code de référence

- `packages/manifest.lua` : format des paquets et dépendances.
- `pkgctl.lua` : résolution, installation et mise à jour.
- `core/startup.lua` : lancement des presets.
- `apps/steamplant/` : exemple de contrôleur avec périphériques.
- `apps/master/` : agrégation, événements, WebBridge.
- `modules/storage/` : backend et protocole Storage.
- `docs/web-package-repository.md` : installation et administration du dépôt Web.
