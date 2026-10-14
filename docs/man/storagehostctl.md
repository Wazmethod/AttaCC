# storagehostctl(1) — Administration de l’hôte Storage

## NOM
**storagehostctl** — inspection, configuration et maintenance du backend persistant.

## SYNOPSIS
```text
storagehostctl
storagehostctl status
storagehostctl configure
storagehostctl backup [destination]
storagehostctl migrate <local|drive>
```

## DESCRIPTION
Binaire installé par `module.storage-server`, à utiliser sur l’hôte. `status` affiche backend, disponibilité et chemin. `configure` modifie les réglages du backend (fichier `/etc/profile.lua`) ; le changement de type de backend s’effectue par `migrate`, pas par un simple configure. `backup` copie et vérifie le JSON. `migrate` copie et vérifie vers le backend demandé, puis enregistre la nouvelle configuration.

## PROCÉDURE DE MIGRATION
1. Sauvegarder le Store actuel et arrêter **toutes** les écritures clientes.
2. Préparer le disque de destination ; il doit être accessible et le fichier de destination absent.
3. Exécuter `storagehostctl migrate drive` (ou `local`), confirmer par `MIGRATE`.
4. Redémarrer l’hôte ; confirmer `status` et les données via `storagectl get`.
5. Ne reprendre les écritures qu’après validation. Le code conserve le fichier source, sans fusion des bases.

## ATTENTION
Le processus ne bloque pas automatiquement les écritures clients. Tester toute migration avec une base de test d’abord.

## VOIR AUSSI
[storagectl](storagectl.md), [validation infrastructure](../validation-infrastructure.md).
