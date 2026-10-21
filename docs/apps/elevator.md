# AttaCC Elevator — ascenseur Create à deux étages

Un ascenseur simple utilisant la boucle SDK AttaCC et **sept bindings**
(`ioctl init` / `/etc/io.lua`). Aucun changement au SDK partagé.

## Branchements

| Rôle | Fonction |
| --- | --- |
| `elevator.call_top` | Bouton d'appel fixe en haut |
| `elevator.call_bottom` | Bouton d'appel fixe en bas |
| `elevator.call_cabin` | Bouton sur le carriage : étage opposé |
| `elevator.at_top` | Redstone Contact à l'étage haut |
| `elevator.at_bottom` | Redstone Contact à l'étage bas |
| `elevator.clutch` | **ON = stop**, OFF = rotation transmise |
| `elevator.gearshift` | Sélection du sens de rotation |

Mécanique : **source de rotation → Clutch → Gearshift → Gantry Shaft**.

Le Bridge actuel (CC: Redstone Link Bridge 1.0.3) fonctionne avec les
paires de fréquences existantes, dont la seconde est maintenant
`minecraft:gold_ingot`. Ne pas utiliser une fréquence vide pour les
sorties : ce Bridge accepte l'appel Lua mais n'émet pas sur cette paire.

## Logique

1. Bouton TOP/BOTTOM : demande de l'étage correspondant **dès ON**.
2. Bouton CABIN : demande de l'étage opposé à l'étage mémorisé.
3. Le contrôleur maintient le Clutch ON, règle le Gearshift, attend
   **250 ms**, puis met le Clutch OFF pour démarrer. Le relâchement du
   bouton n'est pas nécessaire.
4. Le Redstone Contact de destination arrête le moteur via Clutch ON.
5. STOP, ERROR et timeout demandent aussi Clutch ON.

Un deuxième appui pendant le mouvement est ignoré (pas de changement de
destination en route). Les boutons utilisent un front OFF → ON pour ne
pas répéter les demandes lorsque le signal reste actif.

## Configuration (facultative)

Les valeurs par défaut sont dans `apps/elevator/config.lua`. Il est
possible de les surcharger dans
`/etc/attacc/apps/elevator/config.lua` :

```lua
return {
    motion = {
        pollInterval = 0.5,
        settleMs = 250,
        reverseForUp = false,
        timeoutSeconds = 120,
        readOnly = false,
    },
    debug = false,
}
```

Si le fichier existe déjà, conserver les réglages du site et supprimer
les anciens modes expérimentaux `diagnostics.skipInputPolling`,
`diagnostics.bridgeEvents` et `motion.preciseReleaseTimer`, qui ne
sont plus utilisés. Les fréquences restent dans `/etc/io.lua`.

`debug=true` ajoute un compteur et l'âge du dernier polling à la
maintenance. `readOnly=true` laisse les entrées visibles mais bloque
toutes les demandes de mouvement.

Commandes utiles :

```sh
pkgctl update app.elevator
ioctl check
ioctl show elevator.clutch
ioctl show elevator.gearshift
```

Redémarrer l'application après la mise à jour. Le terminal intégré
affiche la maintenance ; les vues du moniteur externe restent disponibles.

## Limites à connaître

Le Bridge 1.0.3 ne dispose pas d'événements de changement de fréquence :
ses cinq entrées sont lues toutes les **500 ms** par défaut. Un pulse
plus court peut être manqué. Le départ suit le premier polling qui
détecte ON, pas nécessairement la milliseconde exacte de l'appui.

**L'arrêt sur contact est lui aussi limité par le polling.** Il faut
valider la vitesse du gantry et la longueur effective du signal au palier.
Des interruptions de timer ont déjà été observées dans ce montage.
Aucun arrêt logiciel ou sans fil n'est garanti en cas de gel de CC,
perte du Bridge ou extinction. Prévoir une coupure mécanique indépendante
et tester d'abord hors charge.

Tests mocks : `tests/elevator_spec.lua` et
`tests/elevator_maintenance_spec.lua`. Ils n'activent pas le gantry.
