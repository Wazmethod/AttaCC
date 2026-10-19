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

Avec des Redstone Links classiques, les deux items de fréquence restent
identiques entre émetteur et récepteur. Si un **Redstone Link Bridge**
(`redstone_link_bridge`) est attaché à la CC, le SDK lit/émet directement
sur cette paire de fréquences : il n'est plus nécessaire de poser un
Redstone Link récepteur supplémentaire devant la CC.

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
redstone de la CC** (ou d'un Redstone Relay CC:Tweaked connecté) : un
changement déclenche un événement `redstone`, traité aussitôt par
Elevator. L'application garde une lecture périodique toutes les 150 ms.
Les versions récentes de CC:Tweaked transmettent aussi cet événement
pour les entrées des Redstone Relays. Avec des Redstone Links Create
intercalés, l'événement est reçu dès que la sortie du **récepteur**
modifie l'entrée CC/relay : vérifier les fréquences et l'éventuelle
latence sans fil.

Dans tous les cas, vérifier en jeu que le contact reste actif assez
longtemps pour être traité, **et que la plateforme ne dépasse pas la
zone de contact avant l'arrêt**. Réduire la vitesse du gantry si
nécessaire.

Ne pas relier les deux capteurs sur une même ligne : l'application doit
distinguer `TOP` et `BOTTOM`.

## 2. Interface CC et Bridge : aucun relais obligatoire

Les **sept rôles logiques** restent indépendants, mais ils peuvent
désormais utiliser trois transports depuis `ioctl init` :

- une face redstone de la CC ;
- une face d'un Redstone Relay CC:Tweaked ;
- un Redstone Link Bridge avec ses deux fréquences Create.

Le Bridge doit être connecté comme périphérique CC:Tweaked
(`ioctl discover` permet de confirmer sa présence). Exemple de câblage
recommandé pour conserver une commande d'entraînement locale :

| Rôle | Transport conseillé | Configuration |
| --- | --- | --- |
| `elevator.call_top` | Bridge | paire d'items du bouton haut |
| `elevator.call_bottom` | Bridge | paire d'items du bouton bas |
| `elevator.call_cabin` | Bridge | paire d'items du bouton cabine |
| `elevator.at_top` | CC locale ou Bridge | contact fixe du haut |
| `elevator.at_bottom` | CC locale ou Bridge | contact fixe du bas |
| `elevator.clutch` | **CC locale** | face raccordée au Clutch |
| `elevator.gearshift` | **CC locale** | face raccordée au Gearshift |

Les contacts câblés directement bénéficient d'événements redstone.
Si le Bridge expose `watchLinkSignal`, Elevator écoute également
`redstone_link_change`. Dans les autres cas, les entrées sont lues
périodiquement : une impulsion plus courte qu'un cycle peut être ratée.

Éviter de piloter le Clutch à travers une liaison sans fil pour la
première recette ; une commande de Clutch via Bridge reste possible
avec le driver, mais **la perte de la liaison ne garantit pas l'arrêt
mécanique**. Aucun Redstone Relay n'est nécessaire dans ce montage.

## 3. Installer et configurer

**Écrans et onglets** : après `pkgctl activate preset.elevator` puis
`reboot`, `startup.lua` lance Elevator dans un **onglet multishell
séparé**. L'onglet 1 conserve le shell CraftOS ; le second onglet affiche
la **maintenance AttaCC** (`STATUS`, `TOOLS`, `REQUIREMENTS`, `RECENT`)
en mode texte. L'interface applicative Elevator est destinée à un
**moniteur externe optionnel**, et ne doit pas remplacer la maintenance
sur le terminal intégré. Exécuter `appctl elevator` manuellement démarre
l'application dans **l'onglet courant**, ce qui n'est pas équivalent
au démarrage automatique après activation du preset.

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

L'assistant `ioctl init` liste les rôles `elevator.*`. Il demande
**d'abord le périphérique** (CC, Redstone Relay, Bridge), puis la
face redstone **ou** les deux fréquences d'items du Bridge. Il
enregistre le tout dans `/etc/io.lua` : les anciennes configurations
`side` / `relay` sont conservées. Les sorties utilisent
`direction=output` ; les boutons et capteurs utilisent
`direction=input`. Si un signal est inversé, adapter `invert`.
Vérifier ensuite `ioctl read elevator.at_top` et les autres entrées.
Voir également [Drivers SDK](../sdk/io-drivers.md).

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

## 4. Pilotage depuis la CC sans moniteur

Après activation du preset, le premier onglet CraftOS est réservé au
shell, le second à la **maintenance AttaCC**. Elevator déclare
maintenant une vraie page de maintenance, avec :

- `STATUS` : étage actuel, phase, destination, contacts, appels,
  confirmation locale en attente et dernière erreur.
- `TOOLS` : **STOP NOW**, **GO TOP x2**, **GO BOTTOM x2**.
- `REQUIREMENTS` : état des sept bindings configurés par `ioctl`.
- `RECENT` : derniers événements du contrôleur.

Cliquer **deux fois** sur `GO BOTTOM x2` ou `GO TOP x2`
à moins de cinq secondes d'intervalle pour confirmer un déplacement.
Après le premier clic, `STATUS / Local command` indique
`CONFIRM go_bottom (click again)` ou `CONFIRM go_top (click again)`.
Le premier clic **ne change aucune sortie**. Changer de destination
ou attendre plus de cinq secondes réarme la confirmation.
`STOP NOW` est exécuté immédiatement, sans double clic.

Ces actions locales appellent les **contrôles SDK existants** :
elles respectent la même machine d'états, le timeout de trajet, les
contacts et les erreurs ; elles ne contournent pas le contrôleur.

### Diagnostic si l'ascenseur reste PREPARING

**Comparer le polling Elevator sans toucher au runtime SDK** :

1. Immobiliser/déconnecter mécaniquement le gantry. Une perte du signal
   de la CC ou du Bridge peut libérer le Clutch Create.
2. Mettre à jour uniquement `app.elevator`.
3. Ouvrir `/etc/attacc/apps/elevator/config.lua` (créer son répertoire
   si nécessaire). Dans la section `motion`, ajouter ou remplacer
   `pollInterval=1.0` et `readOnly=true`. Ne pas écraser les autres
   paramètres existants du site.
4. Redémarrer ; dans `STATUS`, vérifier
   `Commissioning = READ-ONLY / poll 1 s`.
5. Sans essayer de déplacer l'ascenseur, observer `Controller updates`
   et `Diagnostic timer` pendant au moins une minute.

Exemple de fichier **uniquement si aucun override n'existait** :

```lua
return {
    motion = {
        pollInterval = 1.0,
        readOnly = true,
    }
}
```

`readOnly=true` empêche toutes les demandes de déplacement, qu'elles
proviennent des boutons, du moniteur ou du réseau ; `STOP` reste possible.
Le contrôleur tente toutefois d'alimenter le Clutch au démarrage :
le mode logiciel ne remplace pas l'immobilisation mécanique.

Si les deux compteurs restent actifs à 1 s alors qu'ils disparaissaient
à 150 ms, suspecter le nombre d'appels au Bridge/les charges d'I/O
associées. Si même à 1 s les timers cessent, chercher un problème
de délivrance ou de consommation des événements `timer` pendant les
appels périphériques ou dans l'environnement CC:Tweaked.

Une demande de déplacement est maintenant refusée si l'âge du dernier
`controller.update()` est supérieur à
`max(2000 ms, 5 × pollInterval)`, pour ne pas armer un trajet alors que
le contrôleur est déjà figé. **Ce contrôle ne protège pas un trajet
déjà lancé** si les timers sont perdus : prévoir un arrêt physique
indépendant.

Après les tests, remettre `pollInterval=0.15` et retirer
`readOnly=true` uniquement lorsque la cause est corrigée,
les contacts d'arrivée validés et le mécanisme sécurisé.

La temporisation par défaut est de 250 ms, avant envoi de `clutch=false`.
Dans `STATUS`, lire les nouveaux champs :

- `Controller updates` : nombre d'appels à `controller.update()`, avec
  l'âge en millisecondes du dernier appel ; le compteur doit augmenter.
- `Diagnostic timer` : compteur et âge d'un **second timer CraftOS**
  défini dans Elevator seulement. Il n'agit pas sur le moteur et ne modifie
  pas la boucle générique du SDK.
- `Preparing timer` : âge de la préparation, délai restant et valeur
  effective de `motion.settleMs`.

Le runtime SDK a été restauré à sa boucle historique (la même
qu'utilise SteamPlant). Le timer du contrôleur reste à 150 ms, et la
maintenance suit la cadence normale du SDK.

Si `Controller updates` reste figé pendant que `Diagnostic timer`
progresse, le processus reçoit toujours des événements `timer`, mais
le timer principal du SDK n'entraîne plus les appels à
`controller.update()`. Vérifier alors le traitement des identifiants
de timers et les chemins d'événements SDK.

Si les **deux** compteurs sont figés mais que les clics fonctionnent,
vérifier d'abord si les événements `timer` sont encore livrés par
CraftOS. Si aucun événement ne fonctionne, une opération bloquante
reste possible.

Ce témoin n'est **pas un watchdog de sécurité** : sans mise à jour
du contrôleur, le délai de cinq secondes ne peut pas immobiliser
automatiquement un mécanisme. Prévoir un arrêt mécanique indépendant.

En cas de doute, sécuriser mécaniquement l'entraînement avant de
faire les essais.

Si `Controller updates` **n'augmente pas**, la boucle SDK ne reçoit plus
ou ne traite plus les ticks : chercher un blocage du runtime, de l'I/O
ou du rendu, plutôt que modifier les fréquences du Clutch.

Si le compteur **augmente** mais que le délai est anormalement long,
vérifier `/etc/attacc/apps/elevator/config.lua` et
`motion.settleMs`. Les valeurs de temporisation supérieures à 5000 ms
sont désormais refusées.

Si la préparation dépasse 5000 ms au prochain appel périodique,
le contrôleur passe en `ERROR` et renvoie `clutch=true` afin d'éviter
une remise en mouvement tardive. Si les ticks sont eux-mêmes bloqués,
ce garde-fou logiciel ne peut pas fonctionner : une sécurité mécanique
indépendante reste nécessaire.
Il ne faut pas exécuter une seconde instance avec
`appctl elevator` si le preset tourne déjà en onglet 2.

Le moniteur externe est **facultatif** et continue d'afficher
les vues graphiques `ELEVATOR`, `CONTROLS` et `SENSORS`
indépendamment de la maintenance.

**Première recette** : déconnecter mécaniquement l'entraînement
avant de vérifier la commande du Gearshift et le signal de Clutch.
Un Bridge Create sans fil ne garantit pas l'arrêt sur perte de liaison :
ne pas considérer le STOP logiciel comme une sécurité physique.

## 5. Comportement de l'application

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

## 6. Vérification en jeu (une seule recette)

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
