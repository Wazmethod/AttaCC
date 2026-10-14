# Web dashboard

The hosted Web dashboard is a generic AttaCC control plane.

It receives:

- logical networks;
- machine discovery;
- applications;
- reusable modules;
- capabilities;
- telemetry;
- topology;
- runtime state;
- packages;
- events.

Controllable machine cards are generated from the same `ui.app / ui.groups /
ui.controls` descriptors consumed by Pocket.

## Machine inspector

The machine inspector shows:

```text
APPS
MODULES
CAPABILITIES
PROCESSES
PACKAGES
TELEMETRY
```

Administrative actions are explicit: package update/configuration and node
reboot. Arbitrary remote shell execution is not exposed.

## Master bridge

Configure `/etc/webbridge.lua` on the Master. The native
`apps/master/webbridge.lua` is the only CC-side Web bridge implementation.
