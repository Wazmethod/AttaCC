# Runtime services

A **service** is an executable runtime responsibility or foundational runtime
capability.

Service names are displayed as `*.service` units:

```text
core.service
network.service
remote-shell.service
display.service
collector.service
controller.service
workstation.service
supervisor.service
storage.service
webbridge.service
client.service
```

A service may name the binary which performs its work. For example:

```text
remote-shell.service -> sshd.lua
display.service      -> displayd.lua
workstation.service  -> workstationd.lua
supervisor.service   -> supervisord.lua
```

Foundational services such as `core.service` may be embedded and therefore
have no dedicated binary.

Use:

```text
systemctl list
systemctl status <name>.service
systemctl start <name>.service
systemctl stop <name>.service
systemctl restart <name>.service
systemctl enable <name>.service
systemctl disable <name>.service
systemctl dependencies <name>.service
```

The suffix is presentation syntax: `systemctl` accepts both `display` and
`display.service`.

Do not confuse three concepts:

- **capable**: the current preset/config knows the service;
- **enabled**: it is configured to start;
- **active**: its dependency gate is satisfied and it is allowed to run.

Runtime health details are persisted separately and may report degraded/failed
module or process state.

A service may consume several modules. Modules are not subprocesses and do not
receive tabs merely because they are loaded.


## Unit files and local overrides

Package units live in `/usr/lib/infra/systemd/*.service.lua`. Local unit
overrides may be placed in `/etc/systemd/`, while ordinary per-service
configuration is written to `/etc/services/<name>.conf.lua`.

```text
systemctl cat display.service
systemctl edit display.service
systemctl daemon-reload
```

`systemctl status` reports the unit source, active runtime/process state,
associated modules and the latest entries from `/var/log/infra/services/`.
