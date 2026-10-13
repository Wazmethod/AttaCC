# CraftOS shell environment

CraftOS is the maintenance shell for the native runtime.

On an Advanced Computer, boot keeps the shell in the first tab and launches
the preset application in a second tab.

## Common local commands

```text
edit <file>
ls
cd
cp
mv
rm
cat <file>

pkgctl ...
machinectl ...
profilectl ...
storagectl ...
displayctl ...
```

The project does not need to emulate a Unix shell on top of CraftOS.

## Profile editing

```text
profilectl edit
```

The profile is stored in:

```text
/etc/profile.lua
```

## Optional helper tools

Some packages may still provide helpers such as `less`, `console`, `ps`
or `lsmod` during the migration. They are utilities, not the foundation of
the runtime.

## Remote administration

The SSH-like shell is no longer installed by standard presets. Remote actions
should be exposed as explicit network commands by the target application.

## MOTD

The installer may disable the standard CraftOS MOTD to keep boot output clean.
This does not replace the CraftOS shell itself.
