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
