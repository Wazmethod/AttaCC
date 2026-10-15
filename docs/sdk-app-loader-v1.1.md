# AttaCC V1.1 — chargeur d'applications SDK

Le package core.runtime installe désormais `lib/app_loader.lua` et `appctl.lua`.

## Contrat d'entrée

Une app SDK native réside dans `apps/<id>/`. Le fichier `main.lua`
doit **retourner** l'objet application SDK, sans gérer de boucle CraftOS :

```lua
local attacc=require("lib.attacc")
local app=attacc.app("example",{title="Example"})
app:requirements()
require("controller").setup(app)
return app
```

Le fichier `apps/example/controller.lua` retourne un module local :

```lua
local M={}
function M.setup(app)
    app:data("ready",{label="Ready",value=true})
end
return M
```

Le chargeur résout `require("controller")` dans `apps/example/controller.lua`
et `require("lib.attacc")` vers le SDK public ; il n'expose pas de
`require("lib.io_registry")` ou d'autres bibliothèques internes aux
modules métier. Les modules locaux sont mis en cache par application ;
les références circulaires sont rejetées.

## Lancement

```text
pkgctl install app.example
pkgctl run example
```

`pkgctl run` vérifie l'installation du package puis appelle `appctl`,
qui charge l'entrée SDK, vérifie que l'objet retourné porte le bon ID,
puis lance `app:run()`.

La première version n'intègre pas encore les options de lancement propres
à chaque app ; elles feront partie d'un contrat d'application versionné.

## Compatibilité et restrictions

Le chemin `apps/<id>/main.lua` de SteamPlant et des autres applications
actuelles est encore un ancien programme autonome. **Il ne respecte
pas encore le contrat de retour d'un objet SDK** et ne doit pas être lancé
par `appctl` avant sa refonte. Le démarrage historique reste en place.

L'isolation `require()` empêche l'accès accidentel aux bibliothèques
internes via le chargeur, mais ce n'est **pas une sandbox de sécurité** :
le runtime CraftOS et ses API globales restent accessibles. Il faut
prévoir un modèle de permissions/capacités séparé avant d'exécuter
des applications non fiables.

Le chargeur n'a pas été validé en jeu. Tester plus tard après la migration
complète, selon la stratégie de développement V1.1.


## Démarrage automatique via presets (V1.1)

Le runtime CraftOS (`core/startup.lua`) sait maintenant démarrer un preset
en mode SDK natif, en lançant `appctl.lua <id>` plutôt qu'un programme
historique. Le gestionnaire de packages propose :

```text
pkgctl activate preset.example sdk
pkgctl activate preset.example legacy
```

Le preset sélectionné est sauvegardé dans `/etc/preset`, et la sélection
du lanceur SDK est enregistrée dans `/etc/preset_app.lua` :

```lua
return { preset = "example", sdkApp = "example" }
```

Le mode `sdk` exige une application installée, son entrée
`apps/<id>/main.lua`, le lanceur `appctl.lua` et le contrat explicite
`sdkNative=true` sur le package `app.<id>` du manifeste. Le manifeste
du preset peut définir `sdkApp="<id>"` si son nom diffère de l'ID app.

Exemple de définition **pour une application réellement portée** :

```lua
["app.example"] = {
    kind="app",
    sdkNative=true,
    depends={"core.runtime"},
    files={
        {src="apps/example/main.lua",dest="apps/example/main.lua"},
        {src="apps/example/requirements.lua",dest="apps/example/requirements.lua"},
    },
},
["preset.example"] = {
    kind="preset", sdkApp="example",
    depends={"app.example"}, files={},
},
```

Pour les presets intégrés actuels (SteamPlant, Master, Pocket...), le
lancement **legacy demeure le comportement par défaut**. Le manifeste
ne leur attribue pas encore `sdkNative=true` : il faut d'abord que
leurs fichiers `main.lua` retournent un objet SDK et que leurs fonctions
historiques soient migrées. La commande `pkgctl run <id>` vérifie également
ce marqueur pour empêcher de lancer un programme legacy comme app SDK.

Ce mécanisme ne modifie pas automatiquement le mode de démarrage lors de
`pkgctl update` ; l'activation SDK est un choix explicite. Les applications
legacy continuent donc de démarrer pendant toute la période de transition.
