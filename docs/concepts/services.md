# Runtime services

A **service** is a generic runtime capability provided by a machine.

It is not the application itself.

Current services:

| Service | Responsibility |
|---|---|
| `core` | Runtime/lifecycle foundation |
| `network` | Logical network, discovery and message transport |
| `collector` | Physical input collection and telemetry |
| `controller` | Automation/state machines and physical outputs |
| `display` | Local display/dashboard capability |
| `supervisor` | Network aggregation and supervision |
| `webbridge` | Bridge to the hosted Web control plane |
| `client` | Portable/Pocket client capability |
| `storage` | Persistent shared key/value store server |
| `remote-shell` | SSH-like administrative shell over the logical network |

Services may depend on other services. `systemctl` resolves those dependencies.

```text
systemctl list
systemctl status <service>
systemctl start <service>
systemctl stop <service>
systemctl restart <service>
systemctl enable <service>
systemctl disable <service>
systemctl dependencies <service>
```

Three states must not be confused:

- **capable**: the runtime/package contains the service;
- **enabled**: default boot state says it should run;
- **active**: runtime gate is open and dependencies are satisfied.

New generic infrastructure capabilities should become services. Application
logic such as an elevator or Steam Plant should remain a module.
