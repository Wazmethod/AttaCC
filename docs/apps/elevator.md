# AttaCC Elevator — Create Gantry deux étages (SDK 1.1)

**Statut :** application SDK implémentée sur `feature/v1.1-sdk-unification` ;
pas encore validée dans Minecraft. `main`, SteamPlant et la WebUI ne sont
pas modifiés par cette application.

## 1. Principe de fonctionnement

```text
 Bouton HAUT ---- Link TX ~~ Link RX --- call_top ----\
 Bouton BAS  ---- Link TX ~~ Link RX --- call_bottom --\
 Bouton CABINE - Link TX ~~ Link RX --- call_cabin ---+--> CC Elevator SDK
 Contact HAUT -- Link TX ~~ Link RX --- at_top -------+
 Contact BAS --- Link TX ~~ Link RX --- at_bottom ----/
                                                      |
                         +----------------------------+
                         |                            |
                       clutch                      gearshift
                   sortie Redstone              sortie Redstone
                         |                            |
                   [Create Clutch]            [Create Gearshift]
                         \____________ _______________/
                                      |
                            arbre de transmission
                                      |
                                Gantry Shaft
```

**Mécanique recommandée :**

```text
  Source de rotation constante
          |
     Create Clutch        (signal HIGH => arrête la rotation)
          |
     Create Gearshift     (signal HIGH => sens inversé)
          |
       Gantry Shaft       (même alignement que le montage actuel)
          |
     Gantry Carriage      (plateforme)
```

Si la `gearbox` actuelle est déjà un **Gearshift Create**, la conserver ;
sinon remplacer/ajouter un **Gearshift**, seul composant commandé par
Redstone pour inverser. Ajouter **un Clutch Create**, qui permet
d'immobiliser l'ascenseur entre les deux étages. Ne jamais appliquer
le signal de Clutch à un Gantry Shaft par erreur.

**Sept signaux indépendants** sont nécessaires :

| ID SDK `elevator.*` | Sens | Source / action |
| --- | --- | --- |
| `call_top` | input | Récepteur Redstone Link du bouton HAUT |
| `call_bottom` | input | Récepteur Redstone Link du bouton BAS |
| `call_cabin` | input | Récepteur du bouton sur la plateforme |
| `at_top` | input | Capteur/Redstone Contact de l'étage haut |
| `at_bottom` | input | Capteur/Redstone Contact de l'étage bas |
| `clutch` | output | Clutch Create : **HIGH = STOP**, LOW = marche |
| `gearshift` | output | Gearshift Create : HIGH = sens inversé |

Pour chaque liaison sans fil, placer un couple de **Redstone Links Create**
avec les mêmes deux items de fréquence. Le transmetteur lit un signal,
le récepteur émet un signal redstone physique. La CC ne « voit » pas
directement les fréquences : elle lit le signal émis par le bloc
récepteur adjacent, ou par le `redstone_relay` connecté.

**Important :** un Redstone Link monté sur une contraption mobile n'est
pas un transmetteur fiable pendant le mouvement (fonctionnement normal de
Create sur les contraptions assemblées). Le bouton de cabine sert à lancer
un trajet **depuis une plateforme stationnaire** : l'application mémorise
la destination avant que la plateforme se mette à bouger. Pour commander
en cours de trajet, utiliser des commandes SDK distantes ou une autre
architecture ; ce n'est pas prévu avec le bouton mobile.

### Capteurs de niveau

Placer à chaque étage un capteur indépendant qui indique « plateforme
arrivée ici » ; par exemple un `Redstone Contact` fixé au palier, face
à un contact compatible sur la plateforme. Selon le comportement de la
contraption de ta version Create, le contact peut ne s'activer qu'une
fois l'ensemble stabilisé : vérifier chaque étage manuellement avant
d'activer l'automate. Une impulsion suffisamment longue peut également
servir, puisque l'application retient le niveau atteint.

**Avec tes Redstone Contacts Create :** monter une paire de contacts
par étage (un sur le palier fixe, l'autre sur la contraption), face
contre face à la position d'arrêt. Prélever la sortie redstone sur le
contact **fixe**. Les contacts émettent un signal lorsqu'ils se
rencontrent : il ne faut pas confondre le contact avec un détecteur
de rotation ou un signal d'activation permanente du gantry.

Raccorder de préférence les deux contacts fixes **directement aux entrées
redstone de la CC** : un changement déclenche alors un événement
`redstone`, traité immédiatement par Elevator, en complément de la
lecture périodique toutes les 150 ms. Si un Redstone Link / Redstone
Relay est intercalé, l'arrêt continue de fonctionner par interrogation
périodique, mais l'événement `redstone` du contact n'est pas garanti
jusqu'à l'ordinateur. Dans ce cas, vérifier en jeu que le contact reste
actif assez longtemps pour être lu **et que la plateforme ne dépasse
pas la zone de contact avant l'arrêt**. Réduire la vitesse du gantry si
nécessaire.

Ne pas relier les deux capteurs sur une même ligne : l'application doit
distinguer `TOP` et `BOTTOM`.

## 2. Interface CC : six côtés, sept signaux

La CC a six faces redstone. Avec sept signaux logiques, il faut **un
`Redstone Relay` de CC:Tweaked**, accessible depuis la CC par
un **Wired Modem** et son câble. Le relais expose six faces redstone
supplémentaires et est déjà pris en charge par `lib.io_registry`.

Exemple de câblage à adapter selon l'espace :

| Rôle | Périphérique | Face |
| --- | --- | --- |
| `elevator.call_top` | CC | top |
| `elevator.call_bottom` | CC | bottom |
| `elevator.at_top` | CC | left |
| `elevator.at_bottom` | CC | right |
| `elevator.call_cabin` | Redstone Relay | top |
| `elevator.clutch` | Redstone Relay | front |
| `elevator.gearshift` | Redstone Relay | right |

Ce tableau indique des **faces du bloc choisi**, pas des adresses de
Redstone Links. D'autres répartitions sont valides. Si tu n'as pas de
Redstone Relay dans ta version de CC:Tweaked, on pourra adapter aux
câbles redstone groupés d'un mod compatible ou à deux CC. Le mod
`CC: Create Redstone Link` est une autre option *si installé*,
mais l'application initiale n'en dépend pas.

## 3. Installer et configurer

Sur une nouvelle CC AttaCC, définir son identité de machine et son
réseau logique (`systemctl init`). Puis :

```text
pkgctl source test
pkgctl install preset.elevator
ioctl init
ioctl check
pkgctl activate preset.elevator
reboot
```

L'assistant `ioctl init` liste les rôles `elevator.*`, demande la
face redstone, puis demande **0 = CC** ou le nom du
**Redstone Relay**. Il écrit les bindings dans `/etc/io.lua`. Pour
une sortie, les rôles ont `direction=output` ; pour les boutons et
capteurs, `direction=input`. Si une entrée ou sortie est inversée
électriquement, adapter le câblage ou `invert` dans `/etc/io.lua`.
Sur une nouvelle installation, confirmer chaque entrée via
`ioctl read elevator.at_top` (et ainsi de suite).

**Important :** `ioctl init` configure toutes les exigences déclarées
des applications installées sur cette CC. Une CC dédiée Elevator évite de
mélanger les rôles SteamPlant et Elevator.

### Sens de rotation

Le moteur doit tourner toujours dans le même sens, le **Gearshift**
se charge de l'inversion. Par défaut, signal **LOW = montée** et
**HIGH = descente**. Si c'est l'inverse sur ta construction, créer :

```text
/etc/attacc/apps/elevator/config.lua
```

avec :

```lua
return {
    motion={
        reverseForUp=true,
        settleMs=250,
        timeoutSeconds=120
    }
}
```

Le `Clutch` est toujours commandé **HIGH pour stopper** et
**LOW pour démarrer**. Les bindings redstone de `ioctl` doivent
respecter cette polarité.

## 4. Comportement de l'application

- **Bouton HAUT** : demande le palier haut ; **bouton BAS** : le bas.
- **Bouton cabine** : demande l'autre palier *si le capteur actuel
  indique TOP ou BOTTOM* ; si la position est inconnue, utiliser
  une commande explicite TOP/BOTTOM.
- La CC alimente d'abord le Clutch, change la direction, attend
  250 ms (configurable) puis coupe le signal Clutch pour démarrer.
- Arrivée détectée par `at_top` ou `at_bottom` : arrêt du Clutch,
  fin du trajet et incrément du compteur de trajets.
- Les demandes identiques pendant un trajet ne changent rien ;
  les demandes opposées sont ignorées jusqu'à la fin du déplacement.
- Redémarrage : Clutch stoppé au boot ; position reconstruite
  avec les capteurs. Si les deux capteurs sont inactifs, position
  UNKNOWN, mais les commandes explicites TOP/BOTTOM restent possibles.
- Commande `STOP` : immobilise l'ascenseur et annule la destination.
- Quitter normalement l'application (ou provoquer une erreur dans sa boucle
  d'événements SDK) réactive le Clutch avec le nouveau hook
  `shutdown`. Un redémarrage forcé, une perte d'alimentation de la CC,
  une déconnexion du relais ou une panne redstone **ne bénéficient pas**
  de cette garantie. Le Clutch Create s'arrête en recevant HIGH et
  repart lorsque le signal disparaît ; éviter les montages où une perte
  de signal entraînerait une descente dangereuse.
- Un trajet qui dépasse le `timeoutSeconds` configuré provoque un
  arrêt et un état ERROR. Il suffit de `STOP` puis de retenter après
  vérification des capteurs. C'est un garde-fou léger pour ce monde
  Minecraft, pas une logique industrielle.

L'application expose ses données `POSITION`, `MOTION`,
`SENSORS`, `CALL BUTTONS`, `STATISTICS` et les commandes
`go_top`, `go_bottom`, `cabin`, `stop` au réseau SDK,
ainsi que des événements `app.event` :

```text
ELEVATOR_READY
ELEVATOR_REQUEST
ELEVATOR_MOVING
ELEVATOR_ARRIVED
ELEVATOR_STOP
ELEVATOR_ERROR
```

## 5. Vérification en jeu (une seule recette)

1. Lancer `ioctl check` ; vérifier que les **sept rôles**
   redstone sont `OK`.
2. Observer `ioctl read elevator.at_bottom` puis
   `ioctl read elevator.at_top` lorsque la plateforme est aux
   positions correspondantes ; vérifier qu'un seul capteur est actif.
   Vérifier aussi que le signal du contact fixe arrive réellement
   jusqu'à la CC au moment du contact, avant de relier le moteur.
3. Vérifier dans la page SENSORS les trois boutons l'un après l'autre,
   y compris celui de cabine **au repos**.
4. Lancer `go_top` depuis le bas, vérifier le sens, l'arrêt au palier
   haut, puis `go_bottom` depuis le haut.
5. Tester les boutons physiques et STOP ; vérifier que le Clutch
   retient la plateforme pendant l'arrêt et après reboot.
6. Vérifier les commandes SDK et les événements depuis Pocket/Master,
   ainsi que les données dans la WebUI quand WebBridge est en ligne.

Ne pas relier les sorties Gearshift/Clutch à la puissance
mécanique avant d'avoir vérifié les polarités, les deux capteurs et
les commandes redstone. Aucune manipulation n'est requise de SteamPlant.
