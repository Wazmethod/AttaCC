# Remote shell

Every current preset installs the core remote administration service:

```text
service: remote-shell
module:  core.remote-shell
command: ssh
```

It provides an SSH-like administrative shell over the CC:Tweaked logical
network.

## Hostnames

Each host has:

```text
machine.key = stable infrastructure identity
hostname    = human-friendly remote-shell name
```

Example:

```text
machine key: infra:steamplant-main
hostname:    steam-main
physical:    cc:37
```

Set or display it with:

```text
machinectl hostname
machinectl hostname steam-main
```

## Discovery and connection

```text
ssh --scan
ssh steam-main
```

`ssh --scan` caches discovered hostnames locally so shell completion can
suggest them afterwards.

The remote prompt keeps a per-session working directory:

```text
steam-main:/$ systemctl list
steam-main:/$ cd .infra
steam-main:/.infra$ ls
```

Type `exit` or `logout` to disconnect.

## Security model

This is intentionally described as **SSH-like**, not real SSH.

CC:Tweaked modem traffic is not encrypted by this implementation. Access is
restricted to the same logical network, and an optional pre-shared token may be
configured:

```lua
remoteShell = {
    token = "change-me",
}
```

Use a token when untrusted computers share the same modem environment.

## Limitations

The first implementation is a line-oriented administrative shell. It is well
suited to commands such as `systemctl`, `machinectl`, `pkgctl`,
`storagectl`, `ls`, `cat` and similar non-interactive commands.

Programs which need a fully interactive terminal/PTY are not guaranteed to work
remotely yet.
