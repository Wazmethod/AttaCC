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
