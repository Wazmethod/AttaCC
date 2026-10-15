# AttaCC V1.1 — conventions de packaging des applications

## Objectif

Chaque app possède son espace d'installation dédié :

```text
/apps/
  steamplant/
    main.lua
    sdk.lua
    requirements.lua
    config.lua
    controller.lua
    io.lua
    telemetry.lua
    view.lua
    ...
  master/
    main.lua
    ...
  pocket/
    main.lua
    ...
/lib/                 bibliothèques du framework, partagées
/etc/                 identité, secrets, valeurs machine, bindings physiques
/var/lib/attacc/      état persistant du framework
```

Les fichiers du framework ne doivent pas être mélangés aux sources métier.
Le fichier `requirements.lua` est la propriété de l'app ; `ioctl` et le
SDK le découvrent depuis `apps/<id>/requirements.lua`.

## Manifest V1.1

Une application a un nom de package `app.<id>`, `kind="app"` et place ses
sources sous `apps/<id>/`. Exemple :

```lua
["app.generator"] = {
    kind="app",
    depends={"core.runtime","module.network"},
    files={
        {src="apps/generator/main.lua",dest="apps/generator/main.lua"},
        {src="apps/generator/requirements.lua",
            dest="apps/generator/requirements.lua"},
        {src="apps/generator/controller.lua",
            dest="apps/generator/controller.lua"},
    },
}
```

Le gestionnaire refuse désormais qu'un package applicatif écrive dans
`apps/<autre-id>/` ou qu'il écrase un fichier `apps/` appartenant à un autre
package. Les destinations dans `/etc/` restent interdites pour protéger
les réglages propres à la machine.

## Transition en deux phases

**Phase actuellement mise en place :** l'installation de SteamPlant, Master,
Pocket, Workstation et Dashboard crée les copies sous `apps/<id>/` tout en
conservant les anciens points d'entrée et imports dans `lib/`, `modules/`
ou à la racine. Ils servent exclusivement de compatibilité à l'ancien code.
Le `pkgctl` conserve sa procédure de téléchargement préalable,
sauvegarde et restauration en cas d'échec.

**Phase à terminer :** lancer les apps directement depuis `/apps/`,
remplacer les imports historiques par l'objet SDK injecté aux modules métier,
puis supprimer du manifeste les copies de compatibilité et faire nettoyer
leurs anciennes destinations par `pkgctl update`. Ne pas supprimer ces
fichiers avant que le runtime universel remplace complètement les anciens
`main.lua`.

## Requirements et `ioctl`

L'outil `ioctl init` peut analyser les besoins sans exécuter les applications.
Priorité de découverte :

1. `apps/<id>/requirements.lua` — chemin canonique
2. `lib/attacc_requirements_<id>.lua` — secours legacy transitoire

Une app SDK appelle simplement `app:requirements()`. Elle n'importe
aucune bibliothèque interne relative à la résolution des chemins.

## Limites du lot

Ce changement introduit un agencement d'installation et une protection
d'ownership ; **il ne constitue pas encore un basculement de l'exécution**.
Le `main.lua` de SteamPlant contient toujours le host ancien. Les contrats
applicatifs, le bootstrap SDK natif et le retrait définitif des alias legacy
restent à implémenter et valider hors jeu, avant essais finaux sur les CC.
