# Développer des applications, modules et presets AttaCC

> Guide de développement pour le runtime natif **AttaCC 0.31-dev**.
> Les sources de référence du projet sont `apps/`, `modules/`, `core/`, `packages/manifest.lua` et `core/startup.lua`.

## 1. Différence entre app, module et preset

| Élément | Rôle | Exemple |
|---|---|---|
| **App** | Logique métier d'une machine (actions, UI, télémétrie) | `app.steamplant`, `app.master` |
| **Module** | Capacité générique, réutilisable et indépendante de l'app | `module.network`, `module.display` |
| **Preset** | Ensemble installé pour un rôle de machine, avec dépendances | `preset.workstation`, `preset.dashboard` |
| **Core** | Runtime partagé, bus, identité, registres, contrôle, packages | `core.runtime` |

Un preset n'est **pas** une application en soi. Il référence une ou plusieurs apps et leurs dépendances. Pour créer un *nouveau type de machine démarrable*, il faut également connecter son preset au sélecteur de `install.lua`, à `core/startup.lua` et éventuellement à la découverte réseau. L'assistant Web actuel ne réalise pas encore ces étapes automatiquement.

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

1. Ouvrir **Repository > Import a project**.
2. Préparer un ZIP avec des chemins relatifs. Par exemple, avec un dossier cible `apps/example`, l'archive contient `main.lua`, `config.lua`, `controller.lua` et `view.lua`.
3. Renseigner **Target directory** `apps/example`, sélectionner le ZIP, cliquer sur **Import ZIP**.
4. Vérifier les quatre chemins dans le navigateur de sources. Les archives contenant des chemins `..`, des fichiers cachés ou qui écrasent des fichiers présents sont rejetées.
5. Sous **Register package**, choisir `Application`, le nom `example`, ses dépendances, puis contrôler chaque association source → destination CraftOS.
6. Cliquer sur **Create package definition**. L'entrée est ajoutée à `packages/manifest.lua`.
7. Sur un ordinateur de test qui pointe vers le dépôt Web, exécuter `pkgctl source test`, `pkgctl list`, `pkgctl install app.example`.

Pour les presets, ajoutez d'abord leur application et leurs modules ; leurs noms figurent dans la liste de dépendances du preset.

## 4. Exemple minimal de manifeste

```lua
["module.example"] = {
    kind = "module",
    description = "Exemple de module réutilisable",
    depends = { "core.runtime" },
    files = {
        { src = "modules/example_module.lua", dest = "lib/example_module.lua" },
    },
},
["app.example"] = {
    kind = "app",
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

L'ajout d'un paquet par `pkgctl install` ne signifie pas automatiquement qu'il est lancé au boot. Un preset bootable implique des modifications supplémentaires de l'installateur et du runtime.

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

Le dépôt reste publiquement lisible pour permettre l'installation des clients. Les opérations d'administration nécessitent le token Web. N'y mettez jamais de secrets.

L'import ZIP actuel plafonne la taille compressée (12 Mio), la taille annoncée après décompression (24 Mio), et le nombre de fichiers (250). Les fichiers existants ne sont pas écrasés. Il ne s'agit pas encore d'un moteur de publications immuables : une modification locale devient visible dans le dépôt actif. Faites les premiers essais sur une CC de test.

À développer : versions immuables, contrôle syntaxique du manifeste Lua, validation automatique des dépendances, génération guidée d'un preset bootable, tests du runtime sur plusieurs types de machines, historique d'éditions du dépôt et mécanisme de restauration des modifications locales.

## 10. Code de référence

- `packages/manifest.lua` : format des paquets et dépendances.
- `pkgctl.lua` : résolution, installation et mise à jour.
- `core/startup.lua` : lancement des presets.
- `apps/steamplant/` : exemple de contrôleur avec périphériques.
- `apps/master/` : agrégation, événements, WebBridge.
- `modules/storage/` : backend et protocole Storage.
- `docs/web-package-repository.md` : installation et administration du dépôt Web.
