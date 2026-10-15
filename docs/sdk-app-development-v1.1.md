# AttaCC SDK V1.1 — contrat public pour les applications

Statut : **API de développement sur `feature/v1.1-sdk-unification`**.
Les exemples ci-dessous correspondent aux méthodes ajoutées au code, mais le
runtime réseau/HID complet n'a pas encore remplacé les hôtes historiques.

## Principe

Le seul point d'entrée de framework d'une application est :

```lua
local attacc = require("lib.attacc")
local app = attacc.app("example", { title = "Example" })
```

Les modules métiers reçoivent `app` depuis le point d'entrée. Ils n'ont
pas à charger `lib.io_registry`, `lib.network`, `lib.protocol`,
`lib.display` ou d'autres modules internes AttaCC.

## Contrat matériel

Chaque application fournit obligatoirement un fichier statique
`apps/<app>/requirements.lua`, installé comme
`lib/attacc_requirements_<app>.lua`. Il doit être lisible avant le démarrage
de l'application, pour `ioctl init`.

```lua
app:requirements(require("lib.attacc_requirements_example"))
```

Les rôles sont qualifiés automatiquement par le SDK : `example.motor`,
`example.valve`, etc. Les bindings physiques sont conservés dans
`/etc/io.lua` et non dans l'application.

## Façade disponible

| API | Usage | Statut |
|---|---|---|
| `app:requirements(table)` | Déclarer les rôles statiques de l'app | Implémentée |
| `app:device(role)` | Accéder à un rôle logique | Implémentée |
| `device:call(method,...)` | Appeler une méthode de périphérique | Implémentée |
| `device:read([fallback])` | Lire un binding logique | Implémentée |
| `device:write(value[,fallback])` | Écrire un binding logique | Implémentée |
| `app:output(role)` | Sortie logique avec `:set()` et `:get()` | Implémentée |
| `app:config(defaultsTable)` | Définir les valeurs par défaut | Implémentée |
| `app:config("path.to.value")` | Lire la config fusionnée | Implémentée |
| `app:require("module.network")` | Déclarer une dépendance connue | Implémentée |
| `app:checkDependencies()` | Vérifier les dépendances installées | Implémentée |
| `app:run(options)` | Boucle CraftOS pour une app autonome | Première version |
| `app:data()`, `app:control()`, `app:graph()`, `app:view()` | Déclarations | Existantes |
| `app:publish()` | Publier le descripteur local | Existante |

Les dépendances prises en charge par `app:require()` sont pour l'instant
`core.runtime`, `module.network`, `module.display`, et
`module.storage-client`. Une dépendance inconnue échoue explicitement au
démarrage : ce n'est pas encore un gestionnaire de dépendances capable
d'installer automatiquement un package.

### Exemple minimal

```lua
local attacc=require("lib.attacc")
local app=attacc.app("example",{title="Simple Generator"})

app:requirements(require("lib.attacc_requirements_example"))
app:require("core.runtime")
app:config({generator={targetRPM=128}})

local motor=assert(app:device("motor"))
app:data("rpm",{label="Motor speed",unit="rpm",
    read=function()
        local value,err=motor:call("getSpeed")
        if err then return nil end
        return value
    end})
app:control("stop",{label="Stop",requires={"motor"},
    run=function()
        local _,err=motor:call("stop")
        if err then return false,err end
        return true
    end})
app:view("main",{label="Generator",data={"rpm"},controls={"stop"}})

local ok,err=app:run({interval=1})
if not ok then error(err) end
```

**Important :** définir `app:requirements()` à l'exécution ne remplace pas
le fichier statique destiné à `ioctl init`.

### Déclaration de configuration

`app:config({...})` définit les valeurs de repli. La lecture
`app:config("generator.targetRPM")` retourne la configuration fusionnée
fournie par l'installation AttaCC si elle existe, sinon la valeur par défaut.
Les valeurs machine/physiques doivent rester hors de ce fichier.

### Cycle de vie du premier hôte SDK

`app:run()` effectue : vérification des dépendances, vérification des
requirements obligatoires, publication du descripteur, statut actif, puis
boucle de timers et événements CraftOS. Il gère actuellement les
`monitor_touch` et `mouse_click` via le rendu SDK, et accepte
`options.update(app)` ainsi que `options.handlers[event](app,...)`.
À l'arrêt, `app:close()` libère les ressources SDK.

Cette première version est volontairement **locale**. Le transport sécurisé,
les HID avancés, les services de découverte, les snapshots réseau, les
événements distribués et la supervision du runtime existant doivent encore
être intégrés à ce nouvel hôte avant la bascule complète de SteamPlant.

## Séparation des responsabilités

- **AttaCC :** découverte et binding I/O, packages, transports, permissions,
  rendu, HID, configuration, cycle de vie.
- **Application :** séquences, interlocks, états métier, algorithmes,
  contrôles, données, graphes et choix de présentation.

Une API de présence matérielle n'est jamais un substitut à un interlock.
Les méthodes `app:call` et `device:call` ne vérifient pas la sûreté métier.
Les contrôles distants doivent avoir une autorisation explicite.

## État de SteamPlant

`apps/steamplant/sdk.lua` utilise désormais `app:requirements()`.
L'ancien `apps/steamplant/main.lua` continue toutefois d'importer
directement les modules internes AttaCC : il est **encore un hôte historique**.
Il ne sera remplacé qu'une fois que le SDK pourra fournir sans régression
l'ensemble de ses services réseau, affichage, contrôle et supervision.

Il reste notamment : la suppression des imports d'infrastructure dans
SteamPlant, l'injection du SDK dans les modules métier, la migration de
Master/Pocket/Web en rendu natif et la suppression des chemins historiques.
Aucun test en jeu tant que ce portage n'est pas terminé.
