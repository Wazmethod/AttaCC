# AttaCC SDK 1.1 — Drivers de périphériques

Branche d'intégration : `feature/v1.1-sdk-unification`.

Le SDK distingue la **fonction logique** (ex. `elevator.at_top`) et son
**transport matériel**. Les applications déclarent leurs besoins avec
`app:requirements()` ou `app:io()`; `ioctl init` enregistre l'association
dans `/etc/io.lua`.

## Types pris en charge

| Driver / mécanisme | Fonction | Statut |
| --- | --- | --- |
| `cc.redstone` (natif) | Faces redstone de la CC et Redstone Relays | Historique, inchangé |
| `cc.peripheral` (natif) | Périphériques CC:Tweaked et `app:call(role,method,...)` | Historique |
| `create.redstone_link` | Redstone Link Bridge de Create | Nouveau |

Un mod tiers peut être accessible **sans driver** lorsqu'il expose un
périphérique CC:Tweaked : définir `type` avec le type réel du bloc et
utiliser `app:call()`. Pour normaliser ses mesures, états et commandes
avec `app:read()` / `app:write()`, ajouter ensuite un adaptateur
au registre `lib.io_drivers`.

### Diagnostic en jeu

```text
ioctl discover
ioctl inspect <peripheral_name>
ioctl drivers
ioctl init
ioctl check
```

`ioctl inspect` est en lecture seule : il liste les types et méthodes,
mais n'exécute jamais une commande du bloc.

## Driver Create Redstone Link Bridge

Compatible avec les mods suivants pour NeoForge 1.21.1 :

- CC: Redstone Link Bridge — `getLinkSignal(freq1,freq2)`,
  `sendLinkSignal(freq1,freq2,strength)`
- CC: Create Redstone Link — mêmes méthodes, avec en plus
  `watchLinkSignal` / `unwatchLinkSignal` et les couleurs optionnelles

Ces deux mods utilisent le type CC:Tweaked `redstone_link_bridge`.
L'addon *Create: Redstone Link GUI* ne fournit pas lui-même de
périphérique : il permet de sélectionner facilement les fréquences
sur les blocs Create.

`ioctl init` propose le nom de chaque Bridge connecté **après**
la CC et les Redstone Relays. Sélectionner son périphérique puis fournir
les deux identifiants d'items (`minecraft:iron_ingot` et
`minecraft:redstone`, par exemple). Pour un emplacement de fréquence
vide, entrer explicitement `-`.

Exemple du binding enregistré automatiquement :

```lua
return {
    io = {
        bindings = {
            ["elevator.at_top"] = {
                kind = "redstone",
                driver = "create.redstone_link",
                direction = "input",
                peripheral = "redstone_link_bridge_0",
                freq1 = "minecraft:iron_ingot",
                freq2 = "minecraft:redstone",
                invert = false,
            }
        }
    }
}
```

Le driver convertit la puissance reçue (`0..15`) en booléen
(`false` pour 0, `true` autrement). Pour une sortie, il
convertit `false` en 0 et `true` en 15 ; une commande
numérique entre 0 et 15 est aussi acceptée.

Les bindings redstone des anciennes installations, basés sur
`side` et éventuellement `relay`, **restent compatibles**.

Sur la variante CC: Create Redstone Link dotée de `watchLinkSignal`,
le SDK s'abonne au démarrage aux fréquences d'entrée et libère ces
abonnements à l'arrêt. L'application peut traiter l'événement
`redstone_link_change` par un handler SDK. Les bridges plus simples
n'envoient pas cet événement : l'application doit continuer à
interroger ses entrées régulièrement.

### Limites et sécurité

- Le Bridge doit être visible dans `peripheral.getNames()` : poser
  le bloc à côté de la CC ou le raccorder par modem/câble CC:Tweaked.
- Installer un mod n'implique pas que le périphérique est attaché
  à la CC : utiliser `ioctl discover` pour le confirmer.
- Une absence de Bridge, un item mal formaté ou une méthode manquante
  provoque une erreur au `ioctl check` et au démarrage de l'application.
- Le driver ne maintient pas une sécurité physique à la disparition de
  la CC, au déchargement d'un chunk ou à une rupture de liaison.
  Pour Elevator, **ne pas considérer l'émission HIGH vers le Clutch
  comme un arrêt garanti en cas de perte réseau**.
- Le polling peut manquer une impulsion Redstone Link très courte.
  Valider la durée du signal en jeu, en particulier pour les
  Redstone Contacts d'étages.
- Les deux champs optionnels `color1` et `color2` acceptent un entier
  `0xRRGGBB` uniquement pour le mod supportant les couleurs.
  L'assistant n'en demande pas encore : définir ces champs dans
  `/etc/io.lua` uniquement en cas de besoin.

## Étendre le SDK pour un mod supplémentaire

Créer un adaptateur `core/io_driver_<nom>.lua` qui implémente :

```lua
M.matches(peripheralName)                  -- booléen
M.validate(binding,requirement)            -- true | false, error
M.describe(binding)                        -- diagnostic affiché
M.read(binding)                            -- value | nil, error
M.write(binding,value)                     -- true | false, error
-- Facultatif :
M.watch(binding)
M.unwatch(binding)
```

Enregistrer son identifiant dans `core/io_drivers.lua` et
déclarer le fichier dans `packages/manifest.lua` sous `core.runtime`.
Il est ensuite disponible via `io_registry`; `ioctl init` peut être
étendu à son type de périphérique.

La compatibilité automatique n'est possible que si le mod expose
une API CC:Tweaked. Les blocs sans interface CC ont besoin d'un
adaptateur côté mod ou d'une autre interface matérielle.

## Vérification locale (sans GitHub Actions)

Depuis une copie du dépôt dans CraftOS :

```text
tests/io_drivers_spec.lua
tests/elevator_spec.lua
```

Ces scripts utilisent des mocks ; aucune commande réelle n'est
envoyée aux machines Create. La validation dans Minecraft doit
ensuite vérifier les lectures des boutons/contacts et les sorties
Gearshift/Clutch à entraînement déconnecté.
