# Modules

A module is a reusable AttaCC capability. It should not contain machine business
policy.

Examples:

```text
module.network
module.display
module.storage-client
module.storage-server
```

A module may expose data, actions or helpers to applications through normal Lua
APIs and/or `core.bus`.

The application decides when and why a capability is used.

For example, `module.display` knows how to discover and measure a monitor; the
SteamPlant app decides what generator information should be shown on it.

Application-specific adapters may live under the app when they describe business
hardware relationships rather than a reusable primitive.
