# AttaCC — Manuels des commandes

Référence des binaires installés par les paquets AttaCC. Chaque page décrit la syntaxe actuellement implémentée, les fichiers de configuration, les exemples et les précautions.

| Manuel | Fonction |
|---|---|
| [pkgctl(1)](pkgctl.md) | Installation, mises à jour et dépendances |
| [machinectl(1)](machinectl.md) | Identité logique, migration, réseau |
| [profilectl(1)](profilectl.md) | Profil applicatif et synchronisation |
| [storagectl(1)](storagectl.md) | Client Storage, découverte et destination |
| [storagehostctl(1)](storagehostctl.md) | Administration de l’hôte Storage, sauvegarde et migration |
| [ioctl(1)](ioctl.md) | Lectures et écritures des entrées/sorties |
| [webbridgectl(1)](webbridgectl.md) | Noms des réseaux sur WebBridge |

Les manuels sont également accessibles dans l’interface **Web → DOCS → COMMAND MANUALS**, chacun dans sa propre rubrique. Les documents source sont sous `docs/man/` ; la version intégrée au frontend est copiée dans `web/frontend/src/docsReference.js`. En cas de modification des manuels, cette copie doit être régénérée pour préserver leur cohérence.

Voir aussi [guide d’exploitation](../guide-exploitation.md) et [plan de validation](../validation-infrastructure.md).
