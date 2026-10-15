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
    }
}
```

L'initialisation des sorties est **active** au premier véritable lancement ;
les valeurs `bootState` et le câblage doivent donc être vérifiés ensemble.
Ne pas présumer qu'une commande logique `cut` désactive un mécanisme si
l'inversion physique ou le câblage est incorrect.

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
