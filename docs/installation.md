# In-game installation

## Required machines

The current default mapping is:

- CC computer ID `0`: Collector
- CC computer ID `1`: Master / Advanced Server
- CC computer ID `2`: Advanced Pocket Computer

The installer also allows selecting a different role manually.

## Collector wiring

The Collector needs access to these peripheral types:

- `create_target`
- `Create_Speedometer`
- `Create_Stressometer`
- `electric_motor`
- `modular_accumulator`
- a wireless modem

The Create Target must receive a Display Link configured for Boiler Status.

Redstone outputs:

- top -> MAIN clutch
- left -> ALT clutch
- right -> GEN clutch

## Master

The Master needs:

- wireless modem
- wall monitor
- optional speaker

## Pocket

The Pocket needs a wireless modem.

## HTTP installation

`install.lua` downloads the appropriate files from GitHub. Since the repository is private, use a fine-grained GitHub token limited to this repository with **Contents: Read-only**.

If the repository is later made public, the token can be left blank.

HTTP must be enabled/allowed by CC:Tweaked.


## Persistent machine identity

The CC:Tweaked computer ID is treated as a physical identifier only. Production
machines should use a logical identity stored in `machine.local.lua`.

On a fresh install, the installer offers:

1. create a new persistent logical identity;
2. import an identity from a replaced machine;
3. temporarily use `cc:<computerId>`.

For a new machine, prefer a semantic key such as:

```text
infra:steamplant-main
infra:factory-a
infra:storage-main
```

Normal updates preserve `machine.local.lua`.

Check the active identity with:

```text
machinectl status
```

### Replacing a computer

On the old machine:

```text
machinectl export
```

Copy the resulting `IM1-...` code and shut the old computer down.

On the replacement Advanced Computer, run the installer, select the same role,
then choose the identity import option and paste the migration code. You can
also import it afterwards:

```text
machinectl import IM1-...
reboot
```

The physical CC ID may change. The logical machine key, name, label, modules and
tags are retained.

Running two computers with the same logical key at the same time is considered
an identity conflict and is reported by the node discovery layer.
