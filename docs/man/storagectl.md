# storagectl(1) — Client Storage AttaCC

## NOM
**storagectl** — configurer une destination de stockage et lire/écrire des données sur l’hôte sélectionné.

## SYNOPSIS
```text
storagectl
storagectl init
storagectl hosts
storagectl use <machine-key> [namespace]
storagectl target
storagectl ping
storagectl ns
storagectl tree
storagectl list <namespace>
storagectl get <namespace> <key>
storagectl set <namespace> <key> <value|json>
storagectl delete <namespace> <key>
```

## DESCRIPTION
Livré par `module.storage-client`. `hosts` écoute les annonces du réseau logique pendant environ cinq secondes. `init` saisit la clé d’hôte, le namespace de configuration et l’activation de synchronisation ; `use` change la destination. L’option `namespace` de `use` concerne la configuration, et **ne remplace pas** l’argument namespace de `get/set/delete/list`.

`ping` et les opérations de données exigent une clé d’hôte configurée dans `/etc/storage.lua`. L’accès direct au backend local n’est autorisé que si la clé sélectionnée est celle de la machine locale. `ns` liste les namespaces, `tree` parcourt les clés.

## EXEMPLES
```lua
storagectl hosts
storagectl use infra-master attacc.config
storagectl ping
storagectl set attacc.audit smoke-test '"ok"'
storagectl get attacc.audit smoke-test
storagectl delete attacc.audit smoke-test
```

## FICHIERS
`/etc/storage.lua` — destination et configuration de synchronisation ; stocké localement.

## ERREURS ET DÉBOGAGE
« Storage host not configured » : exécuter `storagectl init` ou `use`. Timeout : vérifier la clé exacte, les modems, l’hôte Storage actif et les canaux 4255/4256. L’hôte doit être configuré avec `storagehostctl`, pas avec `storagectl`.

## VOIR AUSSI
[storagehostctl](storagehostctl.md), [profilectl](profilectl.md), [guide d’exploitation](../guide-exploitation.md).
