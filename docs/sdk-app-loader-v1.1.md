# Chargeur d'applications AttaCC SDK V1.1

Le runtime est **exclusivement SDK**. Le point d'entrée de chaque
application est `apps/<id>/main.lua`. Il doit retourner l'objet créé
par `attacc.app(id,options)`, et ne doit ni gérer une boucle CraftOS
ni importer les bibliothèques internes du framework.

```lua
local attacc = require("lib.attacc")
local app = attacc.app("myapp", {title="My application"})
app:requirements()
app:config(require("config"))
local service = require("service").setup(app)
app:lifecycle({
    interval=1,
    start=function() return service.start() end,
    update=function() service.update() end
})
return app
```

Le chargeur `lib.app_loader` résout les modules métier
`require("service")` sous `apps/<id>/service.lua`. Seul
`require("lib.attacc")` est exposé comme import du framework.
Le chargeur n'est pas un bac à sable de sécurité : les API globales
CraftOS restent techniquement accessibles.

## Packaging et démarrage

Le manifeste `packages/manifest.lua` définit le package :
```lua
["app.myapp"]={
    kind="app", sdkNative=true,
    depends={"core.runtime"},
    files={
        {src="apps/myapp/main.lua",dest="apps/myapp/main.lua"},
        {src="apps/myapp/config.lua",dest="apps/myapp/config.lua"},
        {src="apps/myapp/requirements.lua",dest="apps/myapp/requirements.lua"},
        {src="apps/myapp/service.lua",dest="apps/myapp/service.lua"},
    },
},
["preset.myapp"]={
    kind="preset",sdkApp="myapp",depends={"app.myapp"},files={}
},
```

```text
pkgctl install preset.myapp
pkgctl activate preset.myapp
pkgctl run myapp
```

Le démarrage automatique utilise `/etc/preset` et
`/etc/preset_app.lua`, puis lance uniquement `appctl.lua <id>`.
Il n'existe pas d'option d'exécution legacy. Un package non marqué
`sdkNative=true` est refusé à l'activation et à `pkgctl run`.

## Configuration et état

- `apps/<id>/config.lua` fournit les réglages par défaut.
- `/etc/attacc/apps/<id>/config.lua` peut les surcharger.
- `apps/<id>/requirements.lua` déclare les rôles matériels.
- `/etc/io.lua` conserve les associations matérielles, via `ioctl`.
- `app:state(key,value)` persiste les états de l'application dans
  `/var/lib/attacc/apps/<id>/<key>.json`.

Aucune conversion d'états historiques n'est prévue pour SteamPlant :
la première installation part de ses valeurs de démarrage SDK.

## Limites de validation

La bascule des sources ne certifie pas la sûreté matérielle ni la
compatibilité de tous les clients. Les tests et l'audit des commandes,
du transport, du rendu, des interlocks et des restaurations sont à
réaliser avant déploiement. Les autres applications AttaCC doivent être
migrées séparément.
