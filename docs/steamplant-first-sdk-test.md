# Premier essai SteamPlant sous AttaCC SDK V1.1

> **Ne pas effectuer le premier lancement sur une centrale en production.**
> Les sorties Redstone et le moteur sont commandés dès le démarrage normal
> via `controller.prepareBootOutputs()`. Isoler physiquement les actionneurs,
> employer une installation de test et garder la possibilité de couper
> le moteur/les embrayages indépendamment de l'ordinateur.

## 1. Installation fraîche

Sur un **ordinateur CC:Tweaked de test neuf**, déployer la branche
`feature/v1.1-sdk-unification` depuis la source GitHub ou votre proxy
de dépôt configuré. Installer les packages avec :

```text
pkgctl install preset.steamplant
```

Le package `app.steamplant` est entièrement SDK : aucun fichier
SteamPlant n'est installé dans les anciens dossiers `lib/` ou
`modules/`. Le runtime générique reste installé dans `lib/`.

## 2. Configurer et vérifier les périphériques

```text
ioctl init
ioctl check
```

Vérifier les rôles `steamplant.target`, `speedometer`,
`stressometer`, `motor`, `accumulator` et les trois sorties
`main_clutch`, `alternator_clutch`, `gen_clutch`.
Les rôles Redstone exigent une association explicite de côté. Vérifier
les inversions et la topologie réelle avant de commander des sorties.

## 3. Précontrôle sans commandes de sortie

```text
appctl check steamplant
```

Cette commande charge le point d'entrée SDK, vérifie les dépendances et
la présence matérielle, mais ne lance ni `app:run()`, ni
`prepareBootOutputs()`, ni la boucle de régulation. Ce n'est pas
une simulation des sorties et cela ne garantit pas la sûreté électrique.

Avant lancement, examiner `apps/steamplant/config.lua`, en particulier
`bootState` et `motor.direction`. Pour surcharger les valeurs d'une
machine sans modifier les sources, créer :

```text
/etc/attacc/apps/steamplant/config.lua
```

Exemple, **uniquement si cela correspond à la position de sécurité réelle
de votre montage** :

```lua
return {
    bootState = {
        main = "cut", alternator = "cut", gen = "cut", motorRPM = 0,
    },
    commissioning = { allowOutputs = true }
}
```

L'initialisation des sorties est **active** au premier véritable lancement ;
les valeurs `bootState` et le câblage doivent donc être vérifiés ensemble.
Ne pas présumer qu'une commande logique `cut` désactive un mécanisme si
l'inversion physique ou le câblage est incorrect.

Le démarrage normal refuse désormais toute commande de sortie tant que
`commissioning.allowOutputs=true` n’a pas été explicitement configuré.
**Ne déverrouiller que sur un banc de test isolé**, après inspection du
câblage et des paramètres `bootState`. `appctl check` n’exige pas ce
paramètre et reste non actionnant.

## 4. Première exécution contrôlée

Après précontrôle, sécurité physique et inspection des valeurs :

```text
pkgctl activate preset.steamplant
pkgctl run steamplant
```

La commande manuelle et le preset utilisent tous deux
`appctl.lua steamplant`. Il n'y a pas de mode legacy.
Pendant l'essai, garder le réarmement automatique désactivé,
observer le moniteur et relever les éventuelles erreurs de démarrage,
de périphérique ou de transport.

Pour vérifier le démarrage automatique, **arrêter l'application manuelle**
avant de redémarrer l'ordinateur (ne pas exécuter deux contrôleurs
SteamPlant simultanément), puis utiliser `reboot`.

## 5. À transmettre pour corriger les écarts

- La sortie intégrale de `ioctl check` et `appctl check steamplant`
- Les messages de `pkgctl run steamplant` au premier démarrage
- Les positions attendues/observées des trois embrayages et du moteur
- Le type exact des périphériques détectés, sans publier de clés SDK
- La présence ou non d'une interface locale et de télémétrie

## État de l'audit

Le parcours de code a identifié deux dépendances bloquantes à
`lib.config`/`lib.profile_store` dans le matériel SDK et `ioctl` ;
les modifications de la branche les remplacent par `/etc/io.lua`.
L'outil `appctl check` a été ajouté pour réduire le risque de
première vérification.

**Ce document ne valide pas le système en jeu.** Les tests de transitions,
les interlocks, l'authentification distante, l'affichage et le comportement
face à une perte de capteur ou à un reboot restent à vérifier.


## Affichage SDK : terminal CraftOS et moniteur externe

Le runtime SDK distingue désormais **deux surfaces simultanées** :

- L'onglet CraftOS intégré reste en **mode texte exclusivement**. Le SDK
  désactive le mode CC:Graphics sur ce terminal pour préserver les onglets
  multishell et l'accès au shell.
- Le premier périphérique de type `monitor` trouvé reçoit l'interface
  indépendante, avec rendu CC:Graphics lorsque disponible. Les événements
  tactiles du moniteur ne sont pas confondus avec les clics dans l'onglet.

Si plusieurs moniteurs sont présents, choisir le périphérique dans
`/etc/attacc/apps/steamplant/config.lua` :

```lua
return {
    display = { monitorName = "monitor_0" },
    commissioning = { allowOutputs = true },
}
```

Adapter impérativement le nom retourné par `peripheral.getNames()`.
Ne pas réécrire une configuration existante sans recopier les réglages
de sécurité et les valeurs `bootState`.

Après synchronisation du repository Docker, arrêter l'instance active,
mettre à jour `core.runtime`, `module.display` et `app.steamplant`,
puis redémarrer proprement. Ne jamais lancer deux instances du contrôleur.


## Correctifs console et moniteur (SDK V1.1)

- Console CraftOS : outils sous forme de boutons à fond gris, zones tactiles
  `PREV` et `NEXT` alignées sur leur position réelle à l'écran.
- Moniteur externe : conversion des coordonnées `monitor_touch` (caractères
  CraftOS) vers les pixels utilisés par les hitboxes CC:Graphics. Les clics
  de l'onglet ne sont pas acheminés au dashboard graphique.
- SteamPlant : navigation `Overview` / `Graphs` / `Status`,
  pour éviter une très longue suite de pages contenant toutes les
  commandes disponibles ; les commandes sensibles restent dans la
  console native et les contrôles SDK appropriés.
- Test de routage simulé : `tests/sdk-hid-surfaces.lua`.
  Ce test n'a pas été exécuté dans Minecraft lors de ce correctif.

Après avoir synchronisé le repository Web, **arrêter l'instance active**
puis mettre à jour `core.runtime`, `module.display` et
`app.steamplant`, avant un seul redémarrage. Ne pas faire tourner deux
contrôleurs simultanément.


## Correctif tactile graphique et boutons horizontaux

Le moteur d'interface textuelle `lib.maintenance_ui` regroupe les
boutons d'outils horizontalement avec espacement, retour à la ligne
selon la largeur du terminal et zones de clic alignées. Les boutons
n'affichent plus de crochets `[]`.

Le moteur `lib.display_sdk_graphics` teste désormais les zones
rectangulaires en pixels (`x1/y1/x2/y2`) au lieu de réutiliser
le hit-test monoligne de `lib.display_sdk`. Ce bug empêchait
les boutons du moniteur CC:Graphics de répondre malgré leur affichage.
Test de non-régression ajouté : `tests/sdk-graphics-hitboxes.lua`.

**Non validé dans Minecraft lors du commit.** Après synchronisation
du repository Web et arrêt de l'application en cours, mettre à jour
`core.runtime`, `module.display` et `app.steamplant`. Redémarrer,
puis tester d'abord les commandes de navigation non destructives du moniteur
(`OVERVIEW`, `GRAPHS`, `STATUS`) avant toute commande matérielle.


## Profil tactile des Angled Monitors 3x1 (restauration legacy)

L'ancien collector fournissait `display.touchProfile="angled3"` :
les tiers extérieurs ont leur axe X inversé **à l'intérieur du tiers**,
tandis que le tiers central reste inchangé. Cette logique a été reprise
dans `core/sdk_hid.lua` pour le mode CC:Graphics.

Configurer avec `appctl config steamplant` :
`display.touchProfile=angled3`, `display.touchFlipX=false`,
`display.touchFlipY=false`. Les profils disponibles sont
`normal`, `angled3`, `mirror_x`.
Ne pas cumuler `angled3` et `touchFlipX=true`.

L'ancien code de référence se trouve dans
`cc/collector/lib/display.lua` au commit
`121618ec919dbf428c5ed2c6b8ad5f1eae213e60`.
Le comportement reste à valider sur le moniteur dans Minecraft.


## Navigation du moniteur graphique par exports SDK

Le renderer CC:Graphics déduit les trois catégories de `app:descriptor()` :
`DATA` (`descriptor.data`), `GRAPHS` (`descriptor.graphs`),
`CONTROLS` (`descriptor.controls`). Chaque entrée publiée constitue
une sous-catégorie automatiquement sélectionnable, même lorsqu'aucune vue
`app:view` dédiée n'a été créée.

Sur un écran panoramique compact, la barre inférieure sélectionne les
catégories et `PREV/NEXT` parcourt les éléments publiés. La rangée de
sous-catégories affiche un sous-ensemble centré sur l'élément courant,
afin de garder des zones tactiles suffisamment larges.

Dans `CONTROLS`, le moniteur affiche l'état et le libellé des commandes,
mais ne déclenche **aucune sortie physique** au toucher : les commandes
continuent à être exécutées depuis l'interface de maintenance CraftOS.
L'activation tactile nécessitera une étape de confirmation explicite.
Le profil `angled3_swap` est conservé dans le SDK HID.
