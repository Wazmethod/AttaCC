import { useMemo, useState } from "react";
import {
  BookOpen, Boxes, Cpu, HardDrive, ListTree, Network, Server,
  Settings, ShieldCheck, Wrench
} from "lucide-react";
import "./docs.css";

const SECTIONS = [
  {
    id: "overview",
    title: "Overview",
    icon: BookOpen,
    render: () => (
      <>
        <h1>AttaCC</h1>
        <p>
          AttaCC is a native CraftOS application platform for CC:Tweaked.
          A computer runs an application, reusable modules provide generic
          capabilities, and the core supplies the minimal shared runtime.
        </p>
        <pre>{`preset
  -> app
      -> business logic / local UI / view
      -> modules
          -> network / display / storage / I/O
      -> core
          -> runtime / bus / protocol / discovery`}</pre>
        <div className="docs-callout">
          <strong>Rule of thumb</strong>
          <p>
            Apps describe what a machine does. Modules provide reusable
            capabilities. Core contains only shared AttaCC infrastructure.
          </p>
        </div>
      </>
    ),
  },
  {
    id: "filesystem",
    title: "Filesystem",
    icon: ListTree,
    render: () => (
      <>
        <h1>Runtime filesystem</h1>
        <pre>{`/etc/
  machine.lua
  profile.lua
  preset
  webbridge.lua

/var/lib/
  pkgctl/
  attacc/
  storage/
  steamplant/

/var/log/
  attacc/

/run/
  attacc/`}</pre>
        <p>
          Application code is installed by packages. Persistent state belongs
          under <code>/var/lib</code>, runtime state under <code>/run/attacc</code>,
          and logs under <code>/var/log/attacc</code>.
        </p>
      </>
    ),
  },
  {
    id: "boot",
    title: "Boot",
    icon: Server,
    render: () => (
      <>
        <h1>Native boot</h1>
        <pre>{`CraftOS
  -> startup.lua
      -> read /etc/preset
      -> launch selected AttaCC app
      -> optionally launch Web bridge on Master`}</pre>
        <p>
          Pocket runs its app directly in the primary terminal so its interface
          owns focus and input immediately. Other interactive roles may use
          multishell for their local application tab.
        </p>
      </>
    ),
  },
  {
    id: "apps",
    title: "Apps & modules",
    icon: Cpu,
    render: () => (
      <>
        <h1>Applications and modules</h1>
        <pre>{`apps/
  steamplant/
  master/
  pocket/
  workstation/

core/
  bus.lua
  protocol.lua
  nodes.lua
  runtime.lua
  ...

modules/
  network.lua
  display.lua
  storage/`}</pre>
        <p>
          The application directory contains machine-specific behaviour.
          Generic hardware and transport capabilities stay outside applications.
        </p>
      </>
    ),
  },
  {
    id: "machine-apps",
    title: "Controllable machines",
    icon: Network,
    render: () => (
      <>
        <h1>Controllable machine applications</h1>
        <p>
          A controllable app publishes an interface descriptor with its telemetry.
          Pocket, Master and Web consume the same descriptor but render it independently.
        </p>
        <pre>{`ui.app
  id
  title
  machine
  machineLabel
  module
  kind

ui.groups
  metrics grouped by function

ui.controls
  commands linked to groups`}</pre>
        <p>
          On Pocket, DATA, GRAPHS and CONTROLS are top-level categories with independent subpages.\n          Machine selection, events and system administration remain separate pages.\n          The SYSTEM page lets operators select discovered nodes and confirm a reboot.\n          Deploying a new generator, elevator or production machine therefore
          requires its app package, not a machine-specific Pocket or Web patch.
        </p>
      </>
    ),
  },
  {
    id: "display",
    title: "Display",
    icon: Settings,
    render: () => (
      <>
        <h1>Display architecture</h1>
        <pre>{`module.display
  -> discovery
  -> geometry
  -> pagination/layout
  -> input handling

apps/<app>/view.lua
  -> business-specific monitor view

apps/<app>/local UI
  -> maintenance/status in the application terminal`}</pre>
        <p>
          Pocket shows main category tabs along the bottom and subcategory pagination at the top. On a compatible Pocket, press T to toggle the built-in terminal between text and\n          CC:Graphics. An optional external monitor has its own rendering backend.\n          External monitors are optional. Missing or detached displays never stop
          the main application.
        </p>
      </>
    ),
  },
  {
    id: "packages",
    title: "Packages",
    icon: Boxes,
    render: () => (
      <>
        <h1>Package management</h1>
        <pre>{`pkgctl list
pkgctl show app.steamplant
pkgctl install module.storage-server
pkgctl update
pkgctl prune`}</pre>
        <p>
          Presets are dependency roots. Optional capabilities such as the storage
          server are installed only on machines that need them.
        </p>
      </>
    ),
  },
  {
    id: "storage",
    title: "Storage",
    icon: HardDrive,
    render: () => (
      <>
        <h1>Optional shared storage</h1>
        <pre>{`module.storage-client
module.storage-server

# On the Storage host
storagehostctl status
storagehostctl configure
storagehostctl backup
storagehostctl migrate drive
storagectl tree

# On any client (Pocket / Workstation / Master)
storagectl hosts
storagectl use <machine-key> [namespace]
storagectl target
storagectl ping
profilectl push
profilectl pull`}</pre>
        <p>
          Logs use UTC dates in YYYY-MM-DD HH:MM:SS format; previous timestamped\n          log entries remain readable. Storage hosting is independent from the Master role. Local access uses
          the backend directly; remote clients use the AttaCC network transport.
        </p>
      </>
    ),
  },
  {
    id: "install",
    title: "Install",
    icon: Wrench,
    render: () => (
      <>
        <h1>Installation and update</h1>
        <pre>{`install
reboot`}</pre>
        <p>Current presets:</p>
        <pre>{`preset.steamplant
preset.master
preset.pocket
preset.workstation`}</pre>
        <h2>Migration to 0.31</h2>
        <pre>{`install
pkgctl prune
reboot`}</pre>
        <p>
          Run the installer once when migrating from an older package layout so
          the new preset root is installed. Afterwards normal updates use
          <code>pkgctl update</code>.
        </p>
        <h2>Recover a Pocket installation</h2>
        <pre>{`pkgctl install app.pocket\npkgctl update\nreboot`}</pre>
        <p>The Pocket package installs <code>lib/pocket_display.lua</code> and both rendering backends. If a file is missing, reinstall the complete app package rather than copying files from another branch.</p>
        <h2>Web-triggered updates</h2>
        <p>Remote package updates launch <code>runonce.lua</code> in a separate tab. The command runs in an explicit CraftOS environment and reboots only after a successful update. Web administration does not expose an arbitrary shell.</p>
      </>
    ),
  },
  {
    id: "cli",
    title: "CLI reference",
    icon: Wrench,
    render: () => (
      <>
        <h1>Command-line reference</h1>
        <p>Run a binary without arguments or with <code>--help</code> to display its usage where supported. The commands below describe the native runtime binaries and their responsibilities.</p>
        <h2>Storage client: storagectl</h2>
        <pre>{`storagectl hosts                    Discover Storage hosts on the network
storagectl use <machine-key> [namespace]
                                    Select required host and config namespace
storagectl target                   Show configured host and namespace
storagectl ping                     Test connectivity and backend status
storagectl ns                       List namespaces
storagectl tree                     Browse namespaces/keys
storagectl list <namespace>         List keys
storagectl get <namespace> <key>    Read value
storagectl set <namespace> <key> <value|json>
                                    Write value
storagectl delete <namespace> <key>
                                    Delete key`}</pre>
        <p>The Storage client is installed by <code>module.storage-client</code>, including on Master, Pocket and Workstation. Host selection is persisted in <code>/etc/storage.lua</code>. All operations, including ping, require an explicit selected host. The local backend is used only if the selected host is this same machine. Use the persistent machine key, not the display label. Backend configuration does not belong to the client.</p>
        <h2>Storage host: storagehostctl</h2>
        <pre>{`storagehostctl status              Show backend details
storagehostctl configure           Change host backend settings
storagehostctl backup [path]       Copy and verify store
storagehostctl migrate local       Move drive store to local filesystem
storagehostctl migrate drive       Move local store to a labelled data disk`}</pre>
        <p>Only machines with <code>module.storage-server</code> have this command. The Storage process tab also exposes configuration, backup and drive migration. Migrations require pausing client writes, an empty destination, explicit confirmation, verified copying and a host reboot. The source store is retained for rollback. A migration does not merge two existing databases.</p>
        <h2>Machine configuration: profilectl</h2>
        <pre>{`profilectl                         Show help
profilectl show                    Show complete machine configuration
profilectl status                  Show a brief overview
profilectl edit                    Edit local application profile
profilectl push                    Save local identity and profile to Storage
profilectl pull                    Restore configuration from Storage
profilectl machines                List synchronized machine identities
profilectl edit remote <machine-key> [profile|machine]
                                   Edit stored remote configuration
profilectl storage-sync           Enable sync and set timeout; host comes from storagectl
profilectl init                    Initialize local profile
profilectl reset                   Reset local profile`}</pre>
        <p><code>show</code> reads <code>/etc/machine.lua</code>, <code>/etc/profile.lua</code> and <code>/etc/storage.lua</code>. Initial sync should use <code>push</code> when local configuration is authoritative; <code>pull</code> replaces local configuration with the saved version.</p>
        <h2>Machine identity: machinectl</h2>
        <pre>{`machinectl status
machinectl init
machinectl hostname [name]
machinectl export
machinectl import <migration-code>
machinectl reset`}</pre>
        <p>Identity is stored in <code>/etc/machine.lua</code>. Export/import supports moving a logical identity between physical CC computers.</p>
        <h2>Logical I/O: ioctl</h2>
        <pre>{`ioctl list
ioctl show <name>
ioctl read <name>
ioctl write <name> <value>`}</pre>
        <p>Use named logical I/O channels rather than hard-coded peripheral sides.</p>
        <h2>Web bridge administration: webbridgectl</h2>
        <pre>{`webbridgectl configure`}</pre>
        <p>Master-only tool for network label configuration.</p>
        <h2>Package manager: pkgctl</h2>
        <pre>{`pkgctl list
pkgctl status
pkgctl show <package>
pkgctl install <package>
pkgctl update [package]
pkgctl configure <package>
pkgctl prune`}</pre>
        <p>Packages define dependencies, installed binaries and capabilities. See <a href="https://github.com/Wazmethod/steamplant-cc/tree/refactor/native-runtime-v1" target="_blank" rel="noreferrer">source and additional documentation</a>.</p>
      </>
    ),
  },
  {
    id: "validation",
    title: "Audit & troubleshooting",
    icon: ShieldCheck,
    render: () => (
      <>
        <h1>Audit, tests and troubleshooting</h1>
        <p>The complete operational guide, technical findings and end-to-end validation plan are versioned together with the native runtime. Use the links below for the detailed procedures, expected results and known risks.</p>
        <h2>Operational guide</h2>
        <p><a href="https://github.com/Wazmethod/steamplant-cc/blob/refactor/native-runtime-v1/docs/guide-exploitation.md" target="_blank" rel="noreferrer">Read the full operating and debugging manual</a>: roles, startup, packages, Storage, profiles, displays, logs, Web and incident response.</p>
        <h2>Infrastructure validation</h2>
        <p><a href="https://github.com/Wazmethod/steamplant-cc/blob/refactor/native-runtime-v1/docs/validation-infrastructure.md" target="_blank" rel="noreferrer">Open the infrastructure acceptance checklist</a>: 8 phases and 60+ test cases, with pass criteria and rollback precautions.</p>
        <h2>Technical audit</h2>
        <p><a href="https://github.com/Wazmethod/steamplant-cc/blob/refactor/native-runtime-v1/docs/audit-technique.md" target="_blank" rel="noreferrer">Read the code audit and outstanding risks</a>. The inspection is static, not a runtime certification.</p>
        <h2>First-line diagnostics</h2>
        <pre>{`pkgctl status
machinectl status
profilectl show
storagectl target
storagectl hosts
storagectl ping
storagehostctl status    # host only`}</pre>
        <p>For a failed connection, compare network ID, configured machine key and the 4255/4256 channels. For a missing module, inspect package status. For a broken graphic mode, switch Pocket to text using T. For Web issues, inspect the bridge tab and Docker logs.</p>
        <h2>Before production</h2>
        <p>Change the example Machine/Admin tokens, restrict access to telemetry where required, perform a Storage backup and complete the critical cases in the acceptance checklist.</p>
      </>
    ),
  },
  {
    id: "manual",
    title: "Complete manuals",
    icon: BookOpen,
    render: () => (
      <>
        <h1>AttaCC complete documentation</h1>
        <p>These manuals are embedded in the application and kept in step with the repository documentation.</p>
        <h2>Operating and debugging guide</h2>
<pre className="docs-embedded-manual">{`# AttaCC — guide d'exploitation et de validation

Branche de référence : \`refactor/native-runtime-v1\`. Ce guide décrit le code inspecté le 14 octobre 2026 ; il ne constitue pas un procès-verbal de tests en jeu.

## 1. Architecture et responsabilités

\`\`\`text
CraftOS startup.lua
  /etc/preset -> application
  core/       -> état, protocole, profils, découverte, bus
  modules/    -> réseau, affichage, stockage, pagination
  apps/       -> steamplant, master, pocket, workstation, dashboard
  pkgctl.lua  -> manifeste + installation/mise à jour
  webbridge   -> passerelle HTTP/WebSocket vers web/backend
\`\`\`

- **SteamPlant** : télémetrie et contrôle du générateur.
- **Master** : découverte, supervision, événements, agrégation et publication au Pocket.
- **Pocket** : client nomade ; catégories HOME, MACHINE, DATA, GRAPHS, CONTROLS, EVENTS, NETWORK ; sous-pages par catégorie. T bascule manuellement entre texte et CC:Graphics lorsque disponible.
- **Workstation** : accès opérateur, interfaces et outils de maintenance.
- **Storage host** : serveur persistant et réponse aux requêtes Storage, peut coexister avec Master ; indépendant du rôle de la machine.
- **Dashboard** : terminal d'affichage dédié.
- **Web** : serveur Node/Express + WebSocket et frontend. WebBridge fait le lien avec le réseau CC.

## 2. Installer et mettre à jour

\`\`\`lua
pkgctl
pkgctl list
pkgctl status
pkgctl show preset.master
pkgctl install preset.master
pkgctl install module.storage-server
pkgctl update
pkgctl prune
reboot
\`\`\`

Installer un preset fournit ses dépendances. **La présence de \`storagehost.lua\` provoque le démarrage de Storage au boot** ; vérifier ce choix sur chaque nœud. Avant \`pkgctl prune\`, contrôler explicitement les paquets racines à conserver. Ne jamais copier directement des répertoires \`lib/\` d'un autre preset : certains noms sont spécifiques à l'application.

Les fichiers persistants à sauvegarder : \`/etc/machine.lua\`, \`/etc/profile.lua\`, \`/etc/storage.lua\`, \`/etc/preset\`, \`/etc/webbridge.lua\` si applicable, et le fichier Store effectif.

## 3. Storage : client et hôte

\`storagectl\` fait partie de \`module.storage-client\` :

\`\`\`text
storagectl hosts
storagectl use <machine-key> [namespace]
storagectl target
storagectl ping
storagectl ns
storagectl tree
storagectl list <namespace>
storagectl get <namespace> <key>
storagectl set <namespace> <key> <valeur-json-ou-texte>
storagectl delete <namespace> <key>
\`\`\`

\`hosts\` découvre les machines annonçant Storage. \`use\` écrit l'hôte choisi et le namespace de synchronisation dans \`/etc/storage.lua\`. Les opérations Storage, y compris \`ping\`, doivent refuser un hôte non sélectionné. Le backend local ne doit être utilisé que si cet hôte est précisément la machine courante. \`get/set/delete\` reçoivent toujours leur namespace métier propre en argument.

Sur l'hôte seulement, \`module.storage-server\` installe :

\`\`\`text
storagehostctl status
storagehostctl configure
storagehostctl backup [destination]
storagehostctl migrate local
storagehostctl migrate drive
\`\`\`

**Migration prudente** : arrêter les écritures clientes, sauvegarder le fichier actuel, vérifier que la destination n'existe pas déjà, préparer le disque/label, exécuter la migration et confirmer en saisissant \`MIGRATE\`, redémarrer l'hôte, contrôler \`storagehostctl status\`, \`storagectl ping\` puis lire les données. Le code conserve la source et ne fusionne jamais deux bases existantes. Ne pas réactiver les écritures si une étape échoue.

## 4. Profils et identité

\`\`\`text
machinectl           # aide
machinectl status
profilectl           # aide
profilectl show      # configuration effective et fichiers locaux
profilectl storage-sync
profilectl push      # local -> Storage
profilectl pull      # Storage -> local
profilectl machines
profilectl edit
profilectl edit remote <machine-key> [profile|machine]
\`\`\`

Configuration à deux niveaux : \`storagectl use\` sélectionne l'hôte/namespace ; \`profilectl storage-sync\` active la synchronisation et son délai. Au premier déploiement avec un profil local correct, utiliser \`push\` avant \`pull\`. Après \`pull\`, contrôler \`profilectl show\` et redémarrer si la configuration d'une application en cours d'exécution a changé.

## 5. Affichage

Le module \`modules/display.lua\` détecte les périphériques, choisit le backend graphique quand il est disponible et prévoit un repli textuel. Les vues restent propres à chaque application. Les catégories et leur pagination proviennent de \`modules/dashboard.lua\` et \`apps/pocket/pages.lua\`. Le Master et ses agencements sont distincts de Pocket.

**Pocket** : splash texte d'identité réseau au boot, puis démarrage graphique si disponible ; touche \`T\` pour basculer manuellement. Le splash n'est pas un affichage texte simultané à CC:Graphics et ne se rafraîchit pas.

## 6. Journaux et diagnostic

\`runtime.log\` écrit dans le journal central et le journal du composant, via \`core/paths.lua\`. Les nouveaux messages utilisent une date UTC lisible (\`YYYY-MM-DD HH:MM:SS\`) ; les anciennes lignes horodatées restent lisibles via l'API. Contrôler les deux journaux lors d'un échec. L'état d'exécution est accessible par \`runtime.snapshot()\` et exposé au travers des annonces de nœud.

Commandes de base : \`pkgctl status\`, \`machinectl status\`, \`profilectl show\`, \`storagectl target\`, \`storagehostctl status\` (hôte seulement), \`peripherals\` / \`peripheral\` pour le modem et l'affichage, \`ls /lib\` pour vérifier les dépendances.

## 7. Web et sécurité

\`web/docker-compose.yml\` publie par défaut le port 8080, fournit \`MACHINE_TOKEN\` et \`ADMIN_TOKEN\`, et conserve les événements sous \`./data\`. **Ne jamais utiliser les valeurs d'exemple \`change-me-*\`**. Le backend contient actuellement des valeurs de remplacement si les variables sont absentes : c'est un risque à corriger avant une exposition publique. Vérifier que le reverse proxy apporte TLS et contrôle d'accès adapté ; ne pas exposer directement le port d'administration sans protection. Les actions de contrôle et mises à jour via Web nécessitent le token admin.

\`\`\`bash
docker compose config
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 steamplant-web
curl -fsS http://127.0.0.1:8080/api/health
\`\`\`

## 8. Pannes fréquentes et démarche

| Symptôme | Vérification prioritaire | Action |
|---|---|---|
| \`require lib.* not found\` | \`pkgctl status\`, dépendances, preset | \`pkgctl install <paquet>\`, puis mise à jour et reboot |
| Aucun Storage host découvert | Modem sans fil, même réseau logique, annonce \`nodeStatus\`, service actif | Vérifier l'hôte et les annonces |
| \`storagectl ping\` refuse la connexion | \`storagectl target\` | Choisir explicitement \`storagectl use <machine-key> [namespace]\` |
| Timeout Storage | Clé cible, réseau logique, canaux 4255/4256, \`storagehost.lua\` actif | Comparer \`machinectl status\` des deux nœuds |
| \`profilectl pull\` échoue | Activation sync, cible Storage, réponse du serveur | Contrôler \`profilectl storage-sync\`, \`storagectl ping\` |
| Périphérique graphique indisponible | API CC:Graphics, mode de terminal, pile d'affichage | Passer en texte avec T ; conserver le journal |
| Master/SteamPlant absents du Pocket | Modems, canaux, délai de fraîcheur, réseau | Vérifier annonces et l'état Master |
| Web vide/hors ligne | WebBridge, jeton machine, WebSocket, état backend | Contrôler les journaux Web et l'onglet WebBridge |
| Bouton lance une mauvaise commande | Arguments du lanceur \`shell.openTab\` | Tester la commande en shell puis depuis son onglet |

## 9. Référence complémentaire

- [Architecture](architecture.md)
- [Installation](installation.md)
- [Paquets](operations/package-manager.md)
- [Storage et réseau](operations/network-storage.md)
- [Modules](module-development.md)
- [Plan de validation](validation-infrastructure.md)

Les liens sont relatifs au répertoire \`docs/\` et peuvent nécessiter ajustement selon le générateur de documentation.
`}</pre>
<h2>Full infrastructure validation checklist</h2>
<pre className="docs-embedded-manual">{`# AttaCC — validation intégrale de l'infrastructure

**Statut : NON EXÉCUTÉ EN JEU** (plan de recette issu de l'inspection de \`refactor/native-runtime-v1\`, 14 octobre 2026).

Inscrire pour chaque cas : date/heure, rôle, Computer ID, hostname, réseau, résultat **PASS/FAIL**, capture ou journal, et commit GitHub installé. Ne pas effectuer les tests destructifs sur des données de production sans sauvegarde.

## Prérequis et inventaire

Créer une feuille de résultats pour les nœuds : SteamPlant, Master, Storage host (éventuellement même CC), Workstation, Pocket, Dashboard et WebBridge. Noter pour chaque nœud : clé logique, Computer ID, réseau, version/preset, modem, périphériques et chemin réel du Store. Séparer les environnements test et production.

### Phase A — intégrité et démarrage (A01–A07)

| ID | Test | Commande/action | Attendu |
|---|---|---|---|
| A01 | Paquets installés | \`pkgctl status\` sur chaque rôle | Aucun \`MISSING\`, dépendances complètes |
| A02 | Preset et identité | \`cat /etc/preset\`, \`machinectl status\` | Rôle et identité uniques et cohérents |
| A03 | Profil complet | \`profilectl show\` | Identité, profil, Storage et configuration effective lisibles |
| A04 | Reboot | \`reboot\` sur chaque machine, une par une | Chaque application et service prévu redémarre |
| A05 | Service optionnel | Inspecter onglets Master/Storage/WebBridge | Aucun processus serveur inattendu |
| A06 | Modules manquants | Vérifier \`ls /lib\` et \`pkgctl status\` | Aucune erreur \`require\` à l'exécution |
| A07 | Shell/help | Appeler \`pkgctl\`, \`storagectl\`, \`profilectl\`, \`machinectl\`, \`ioctl\` sans paramètres | Aide lisible et pas d'erreur |

### Phase B — réseau et découverte (B01–B07)

| ID | Test | Action | Attendu |
|---|---|---|---|
| B01 | Matériel réseau | Inspecter les modems sans fil sur tous les nœuds | Modems opérationnels |
| B02 | Découverte des nœuds | Page NETWORK Master/Pocket | Toutes les machines attendues, sans collision de clés |
| B03 | Découverte Storage | \`storagectl hosts\` depuis Workstation et Pocket | Fin en ~5 secondes ; clé exacte de l'hôte |
| B04 | Réseau incorrect | Utiliser une machine de test d'un autre réseau logique | Aucun mélange inattendu d'annonces |
| B05 | Déconnexion | Éteindre temporairement un nœud non critique | Il devient indisponible après expiration |
| B06 | Retour réseau | Redémarrer le nœud de test | Retour automatique, statut cohérent |
| B07 | Conflit d'identité | **Seulement en labo**, simuler une clé dupliquée | Alerte de conflit sans reboot intempestif |

### Phase C — Storage / synchronisation (C01–C12)

| ID | Test | Action | Attendu |
|---|---|---|---|
| C01 | Aucun hôte sélectionné | Sur client de test vierge, \`storagectl ping\` | Refus explicite, aucune découverte implicite |
| C02 | Affichage cible | \`storagectl target\` | Clé et namespace cohérents |
| C03 | Sélection | \`storagectl use <clé-hôte> attacc.config\` | Cible enregistrée |
| C04 | Ping ciblé | \`storagectl ping\` | Réponse du seul hôte configuré |
| C05 | Cible invalide | Choisir temporairement une fausse clé, puis \`ping\` | Timeout clair, aucune réponse d'un autre serveur |
| C06 | Test de données | \`storagectl set attacc.audit test-01 ok\` puis \`get\` | \`ok\` restitué |
| C07 | Listage | \`storagectl list attacc.audit\`, \`storagectl tree\` | Clé visible |
| C08 | Suppression | \`storagectl delete attacc.audit test-01\` | Clé absente après suppression |
| C09 | Sync initiale | \`profilectl storage-sync\`, \`profilectl push\` | Sauvegarde distante confirmée |
| C10 | Lecture distante | \`profilectl machines\` ; \`profilectl pull\` sur machine test | Configuration restaurée ; comparer \`profilectl show\` |
| C11 | Hôte en panne | Couper temporairement l'hôte dans un environnement de test | Timeout, aucune substitution silencieuse |
| C12 | Accès local explicite | Sur hôte, sélectionner sa clé puis \`storagectl ping\` ; changer la cible pour une fausse clé | Accès local uniquement avec clé exacte |

**Avant de faire C05**, noter et restaurer la clé réelle via \`storagectl use\`. **Avant C10**, sauvegarder les trois fichiers \`/etc/\` sur la machine de test.

### Phase D — backend, sauvegarde et migration (D01–D06)

| ID | Test | Action | Attendu |
|---|---|---|---|
| D01 | Santé serveur | \`storagehostctl status\` | Backend disponible, chemin et compteurs cohérents |
| D02 | Boutons d'onglet | Status / Tree / Backup / Config / Migrate | Ouverture de l'outil correct, paramètres corrects |
| D03 | Sauvegarde | \`storagehostctl backup\` | Copie vérifiée, source inchangée |
| D04 | Disque absent | **Labo uniquement**, retirer un disque de test | Dégradation visible, pas de corruption silencieuse |
| D05 | Migration | **Labo uniquement**, \`storagehostctl migrate drive\` avec disque vierge | Copie vérifiée, source conservée, redémarrage puis lecture identique |
| D06 | Refus écrasement | **Labo uniquement**, destination avec base préexistante | Refus de la migration et aucune perte de données |

### Phase E — SteamPlant et contrôle (E01–E06)

| ID | Test | Action | Attendu |
|---|---|---|---|
| E01 | Télémétrie | Lire état, eau, chaleur, RPM | Données cohérentes, rafraîchissement Master/Web/Pocket |
| E02 | Catégories | DATA / GRAPHS / CONTROLS | Ordre correct, pas de métriques mélangées |
| E03 | Graphes | Laisser tourner plusieurs minutes | Historique se remplit, unités/axes corrects |
| E04 | Commande sûre | Action non destructive autorisée | Accusé réception et changement d'état |
| E05 | Perte ACK | **Labo uniquement**, couper une source de réponse | Délai/erreur visibles, pas de commande infinie |
| E06 | Actions dangereuses | Contrôler la confirmation/autorisation des actions impactantes | Aucune action accidentelle |

### Phase F — Master et Pocket (F01–F10)

| ID | Test | Action | Attendu |
|---|---|---|---|
| F01 | Layout Master | Parcourir toutes ses pages | Aucun chevauchement, navigation intacte |
| F02 | Pocket splash | Redémarrer Pocket | Logo/identité réseau texte brièvement avant l'interface |
| F03 | Pocket texte | \`T\` pour passer en texte | Affichage texte exploitable |
| F04 | Pocket CC:Graphics | \`T\` pour revenir en graphique | Affichage et interactions préservés |
| F05 | Pocket sans API graphique | **Labo / autre configuration**, retirer compatibilité | Repli texte, aucun crash |
| F06 | Sous-pages | DATA / GRAPHS / CONTROLS ; flèches | Titres en haut, catégories en bas, index indépendant |
| F07 | Événements | Générer un événement non critique | Colonnes HOSTNAME / CODE / INFO dans les deux rendus |
| F08 | Sélection machine | Changer d'app sur Pocket | Télémétrie et contrôles ciblent la bonne machine |
| F09 | Redémarrage distant | **Machine de test uniquement**, sélectionner puis confirmer | Seule la cible choisie redémarre |
| F10 | Modem perdu | **Labo**, déconnecter réseau | État Offline explicite, interface utilisable |

### Phase G — Web / Docker / droits (G01–G08)

| ID | Test | Action | Attendu |
|---|---|---|---|
| G01 | Docker | \`docker compose ps\`, \`docker compose logs --tail=100\` | Conteneur sain, pas de boucle de redémarrage |
| G02 | Santé HTTP | \`curl -fsS http://127.0.0.1:8080/api/health\` | Réponse HTTP correcte |
| G03 | Bridge | Vérifier lien WebBridge ↔ Web | Bridge connecté, réseaux visibles |
| G04 | Documentation | Parcourir tous les onglets DOCS | Layout desktop/mobile correct, CLI à jour |
| G05 | Refus sans token | Requête POST admin sans authentification | HTTP 401, action non exécutée |
| G06 | Tokens | Vérifier valeurs réelles dans le compose (ne **jamais** publier les tokens) | Tokens non vides, non par défaut et différents |
| G07 | Actions ciblées | Sur machine test, déclencher action Web | Bonne cible, ACK, pas d'exécution libre de shell |
| G08 | Persistance | Redémarrer le conteneur de test | Historique stocké dans le volume conservé |

### Phase H — résilience et régression (H01–H06)

| ID | Test | Action | Attendu |
|---|---|---|---|
| H01 | Update locale | \`pkgctl update\` sur un nœud de test | Aucun module manquant après reboot |
| H02 | Update Web | Mise à jour pilotée depuis le Web sur nœud test | Onglet, retour de commande et reboot attendus |
| H03 | Journaux | Déclencher un événement informatif | Date UTC lisible, composant et niveau corrects |
| H04 | Durée | 30 à 60 minutes sur tous les rôles | Pas de freeze, fuite mémoire apparente, spam logs |
| H05 | Redémarrage ordonné | Web, Master, Pocket, SteamPlant dans des ordres différents | Reconnexion sans configuration manuelle |
| H06 | Restauration | **Labo uniquement**, restaurer Store et profil depuis sauvegardes | Identités et données retrouvées |

## Critères d'acceptation

**Blocants** : échec de C01/C04/C12 (destination Storage), D03 (backup), E04/E06 (contrôles), F09 (reboot ciblé), G05/G06 (auth) et H01 (update). Les tests destructifs ne doivent pas être exécutés sur le monde principal.

Consigner les résultats par exemple :

\`\`\`text
Date/heure UTC :
Branche / commit installé :
Nœud / Computer ID / clé :
Test ID :
PASS / FAIL / NON TESTÉ :
Commande ou action :
Résultat observé :
Résultat attendu :
Logs / capture :
Correction ou ticket :
\`\`\`

Ne considérer la recette globale comme terminée qu'après validation de tous les cas applicables et correction ou acceptation documentée des écarts.
`}</pre>
<h2>Technical audit</h2>
<pre className="docs-embedded-manual">{`# Audit technique — AttaCC Native Runtime

Date : 2026-10-14. Référence : \`refactor/native-runtime-v1\`.

**Méthode** : inspection statique des points d'entrée, du manifeste, du runtime, des outils Storage, du Pocket, du backend Web et de la documentation. Aucune instance Minecraft/CC ni conteneur utilisateur n'est accessible depuis cette revue ; les tests fonctionnels restent à exécuter. Les constats ci-dessous indiquent ce que le code prouve, et non un fonctionnement constaté dans le jeu.

## Constats confirmés par lecture du code

| ID | Niveau | Fichier / comportement | Conséquence et recommandation |
|---|---|---|---|
| SEC-01 | **Critique avant exposition publique** | \`web/backend/server.js\` substitue \`change-me-machine-token\` et \`change-me-admin-token\` quand les variables sont absentes ; \`web/.env.example\` propose ces valeurs. | Utiliser deux secrets forts, différents ; renforcer ultérieurement le démarrage pour refuser les valeurs d'exemple. Tester l'auth sans token. |
| SEC-02 | **À décider selon périmètre Web** | \`/api/status\`, \`/api/networks\`, \`/api/events\` et \`/ws/browser\` exposent des données sans authentification applicative, alors que les routes d'administration exigent un token. | Si l'interface ne doit pas être publique, ajouter contrôle d'accès côté proxy ou dans l'application. |
| SEC-03 | **Risque logique réseau** | \`modules/storage/network_store.lua\` autorise les opérations définies dans le protocole quand la cible et le réseau correspondent ; aucune authentification forte du modem ne figure dans ce module. | Un autre CC du même réseau logique pourrait émettre des requêtes Storage. Prévoir autorisation d'origine et protection des commandes mutantes si adversaires possibles. |
| OPS-01 | **Risque migration** | \`storagehostctl migrate\` copie et vérifie le fichier avant de sélectionner le nouveau backend, mais n'interdit pas simultanément les écritures clients. | Arrêter les écritures pour toute migration ; tester sur un disque vierge. Un mode maintenance serveur serait préférable. |
| OPS-02 | **Risque écriture** | Les écritures du backend reposent sur un fichier JSON et un remplacement \`.new\` ; aucune transaction inter-processus globale n'est apparente. | Tester coupures, limites de taille, sauvegardes et appels simultanés. |
| OPS-03 | **Risque déploiement** | \`core/startup.lua\` lance le serveur Storage si \`storagehost.lua\` est installé, indépendamment de la présence d'un preset serveur. | Contrôler explicitement les racines installées et l'usage de \`pkgctl prune\`. |
| GUI-01 | **Limite confirmée** | Le Pocket active CC:Graphics sur le terminal principal : ce n'est pas une surface textuelle distincte. | Le splash réseau est visible avant le lancement graphique ; il n'est pas garanti visible ensuite en parallèle. |
| OPS-04 | **Risque disponibilité** | Mise à jour de paquet et opérations de configuration exécutées en CraftOS peuvent dépendre de l'environnement shell/multishell. | Tester systématiquement lancer en CLI, depuis un bouton et depuis Web ; vérifier les erreurs et le redémarrage. |

## Comportements récemment corrigés, à tester

- Découverte Storage : timer borné à cinq secondes.
- Sélection du Storage : \`storagectl use\` est obligatoire, y compris pour les appels locaux ; \`ping\` ne doit pas interroger un hôte quelconque.
- Les réponses Storage côté client sont filtrées par la clé de l'hôte sélectionné.
- \`profilectl storage-sync\` n'exige plus une seconde saisie de l'hôte.
- Boutons de l'onglet Storage : invocation \`shell.openTab\`.
- Bouton Network Labels WebBridge : passe l'argument \`configure\`.
- Pocket : titres/sous-pages, événements HOSTNAME/CODE/INFO, splash AttaCC et bascule \`T\`.

## Manques de validation

La présente revue ne constitue pas une preuve de compilation ou d'exécution des 100 fichiers du dépôt. À compléter avec : analyse syntaxique Lua compatible CraftOS, build Vite, tests unitaires sur protocole/Storage/profils, simulations de coupure, et la recette end-to-end. Aucun feu vert de production ne doit être déduit du seul audit statique.

## Plan d'amélioration priorisé

1. **P0** : secrets Web forts, accès à la télémétrie selon la politique voulue, test des autorisations d'actions et reboot.
2. **P0** : recette Storage sans destination puis avec destination exacte ; sauvegarde et restauration validées.
3. **P1** : maintenance Storage bloquant les écritures pendant migration et contrôles post-migration.
4. **P1** : intégration continue (analyse Lua, build frontend, lint, validation du manifeste).
5. **P2** : tests automatisés d'UI Pocket/Master, télémétrie et reconnexion WebBridge.

Document de référence : [validation-infrastructure.md](validation-infrastructure.md).
`}</pre>
      </>
    ),
  },
  {
    id: "security",
    title: "Safety",
    icon: ShieldCheck,
    render: () => (
      <>
        <h1>Safety boundaries</h1>
        <p>
          Web administration uses the configured admin token. The control plane
          exposes declared application actions and package administration, not
          arbitrary remote shell execution.
        </p>
        <p>
          Application control continues independently from optional displays and
          from the Web bridge.
        </p>
      </>
    ),
  },
];

export default function DocsView() {
  const [section, setSection] = useState("overview");
  const active = useMemo(
    () => SECTIONS.find(item => item.id === section) || SECTIONS[0],
    [section]
  );
  const Icon = active.icon;

  return (
    <main className="docs-page">
      <aside className="mc-panel docs-sidebar">
        <div className="docs-sidebar-title">
          <BookOpen size={18} />
          <div>
            <strong>ATTACC DOCUMENTATION</strong>
            <small>0.31 native runtime</small>
          </div>
        </div>

        <nav>
          {SECTIONS.map(item => {
            const ItemIcon = item.icon;
            return (
              <button
                key={item.id}
                className={section === item.id ? "active" : ""}
                onClick={() => setSection(item.id)}
              >
                <ItemIcon size={16} />
                {item.title}
              </button>
            );
          })}
        </nav>
      </aside>

      <section className="mc-panel docs-content docs-article">
        <div className="docs-content-title">
          <Icon size={20} />
          <span>{active.title}</span>
        </div>
        {active.render()}
      </section>
    </main>
  );
}
