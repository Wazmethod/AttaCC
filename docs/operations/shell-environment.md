# Shell environment

Every current preset receives the `runtime.shell-tools` package.

It provides:

- infrastructure command aliases;
- argument completion for the administration commands;
- cached hostname completion for `ssh`;
- the local `less` pager;
- CraftOS MOTD suppression.

## Profile editing

Use:

```text
profilectl edit
```

The profile is stored in:

```text
/etc/profile.lua
```

If no override exists yet, `profilectl edit` creates an empty override and
opens it in the CraftOS editor.

`profilectl show` is retained only as a hidden compatibility alias.

## Pager

```text
less <file>
less -n <file>
```

Keys:

```text
Up/Down or j/k   line navigation
PgUp/PgDn        page navigation
Home/g           beginning
End              end
/                search
n                next match
q                quit
```

The pager is intended for the local terminal. The current remote shell is
line-oriented and does not yet provide a PTY suitable for interactive programs
such as `less` or `edit`.

## Completion

The shell environment registers completions for:

```text
machinectl
profilectl
systemctl
pkgctl
storagectl
ssh
```

Machine/profile configuration is stored directly below `/etc`, rather than
as root-level `*.lua` files. This prevents configuration files such as the
legacy `machine.local.lua` from competing with commands such as
`machinectl` during program completion.

Run `ssh --scan` to refresh the hostname cache used by SSH completion.

## MOTD

The installer and package manager persist:

```lua
settings.set("motd.enable", false)
settings.save()
```

so the standard CraftOS MOTD is disabled on subsequent boots.


## External monitor console

The built-in Advanced Computer terminal has a fixed character grid. For a
larger terminal, redirect a shell to an attached Advanced Monitor:

```text
console
console top
console top 0.5
```

The first form uses the first attached monitor. The optional second argument is
the monitor peripheral name and the third argument is the text scale.

The keyboard remains attached to the Computer running the command; the monitor
acts as the terminal display. Type `exit` to restore the Computer terminal.
