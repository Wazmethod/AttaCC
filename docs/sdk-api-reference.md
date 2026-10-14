# AttaCC SDK — Référence des API CraftOS

Référence basée sur le code V0.34 de `core/`. Les modules sont installés par `core.runtime` sous `lib/` ; les exemples utilisent `require("lib.nom")`. Le SDK ne nécessite pas de compilation.

## État et journalisation (`lib.runtime`)

| Appel | Fonction |
|---|---|
| `runtime.set(name, status, details)` | Met à jour un état local persistant dans `/run/attacc/state.json`; retourne le résultat de l'écriture |
| `runtime.remove(name)` | Supprime un état |
| `runtime.snapshot()` | Retourne un objet avec `entries` et `updatedAt` |
| `runtime.log(component, level, message)` | Écrit une entrée dans le journal global et celui du composant |
| `runtime.logs(limit, component)` | Récupère les dernières entrées (jusqu'à 200), en incluant le journal tournant |
| `runtime.logPath(component)` | Renvoie le chemin du journal global ou du composant |

```lua
local runtime = require("lib.runtime")
runtime.set("my-app", "ready", { message = "Initialisation terminée" })
runtime.log("my-app", "info", "Application démarrée")
```

Consulter ensuite `logctl status`, `logctl tail 50`, `logctl errors`. `ready` indique uniquement ce que l'application a déclaré, pas une surveillance automatique.

## Bus d'événements local (`lib.bus`)

| Appel | Fonction |
|---|---|
| `bus.on(topic, handler)` | Abonne un handler, retourne un token |
| `bus.off(token)` | Désabonne ce token |
| `bus.emit(topic, payload, meta)` | Place un événement `attacc_bus` dans la queue CraftOS |
| `bus.handle(event, topic, payload, meta)` | Distribue l'événement aux abonnés et retourne s'il y avait un abonné |
| `bus.dispatch(...)` | Alias pratique de `handle` |

Le bus **n'est pas un réseau** : les événements passent par la boucle d'événements de l'ordinateur Lua courant. Les handlers doivent être servis par `bus.handle`.

```lua
local bus = require("lib.bus")
local token = bus.on("example.ping", function(payload)
    print(payload.message)
end)
bus.emit("example.ping", { message = "Bonjour" })
local ev, a, b, c = os.pullEvent()
bus.handle(ev, a, b, c)
bus.off(token)
```

Les topics `example.*` permettent un abonnement préfixé. Un handler qui échoue produit un événement `attacc_bus_error`.

## Routage de modules (`lib.module_router`)

`local router = require("lib.module_router").new()`

- `router:register(moduleName, handler)` : enregistre un handler sous un nom.
- `router:dispatch(message, ...)` : refuse les messages mal formés et ceux d'un autre réseau déclaré ; retourne `false` si aucun handler n'est choisi.
- `router:list()` : retourne les noms enregistrés.

**Important :** ce routage filtre un champ réseau fourni par le message, mais n'authentifie pas l'expéditeur. Le handler doit valider ses propres arguments avant d'agir.

## Périphériques et redstone (`lib.io_registry`)

- `io.requirements()`, `io.validateRequirements()` : exigences matérielles et état de validation.
- `io.candidates(role)`, `io.resolve(role)` : candidates et résolution d'un rôle.
- `io.list()`, `io.describe(name)` : liste ou description des bindings.
- `io.read(name)` retourne `value` ou `nil, err`.
- `io.write(name, value)` retourne `true` ou `false, err`.

```lua
local io = require("lib.io_registry")
local value, err = io.read("sensor")
if value == nil then printError(err) else print(value) end
```

La clé `sensor` n'est qu'un **exemple** : elle doit réellement être déclarée dans les bindings de la CC. Ne jamais supposer qu'un périphérique ou un côté redstone existe. Les réglages I/O résident notamment dans `/etc/io.lua`.

## Réseau (`lib.protocol`)

- `protocol.now()` : epoch UTC en millisecondes.
- `protocol.findWirelessModem()` : premier modem sans fil trouvé ou `nil`.
- `protocol.send(modem, channel, message)` : transmet sur le canal.
- `protocol.makeModuleCommand(moduleName, command, origin, id, args, targetMachine)` : construit un message selon l'identité locale.
- `protocol.normalizeModuleCommand(message, moduleName)` : retourne le message compatible ou `nil`.
- `protocol.validateCommand(message, moduleName, network, maxAgeMs)` : vérification facultative de structure et d'ancienneté, **pas** d'authentification.

Tester le modem avant `send` ; les ordinateurs de poche et ordinateurs ordinaires peuvent ne pas avoir les mêmes équipements.

## Structure du package

Chaque app ou module a un nom (`app.mon-app`), des dépendances (`depends`), une version propre facultative (`version`) et les associations `files = { { src, dest } }`. Une version absente hérite de la version du manifeste. Les chemins d'installation de `lib/` doivent correspondre aux noms employés par `require`.

Voir [le guide développeur](developper-apps-modules-presets.md) et [l'exemple exécutable](../examples/sdk-hello/README.md).
