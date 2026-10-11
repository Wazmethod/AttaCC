# Network shared storage

The supervisor/Master provides a small persistent network key/value store.

```text
service = storage
module  = network.storage
```

It is intended for small shared infrastructure data:

- shared configuration fragments;
- coordination state;
- module metadata;
- lightweight inventories;
- distributed feature flags;
- future locks/leases.

It is **not** a distributed filesystem and should not be used for large blobs.

## Persistence

The Master stores data in:

```text
.infra/storage/store.json
```

Values are grouped by namespace and key.

Current default limits:

```text
max value size = 4096 serialized bytes
max keys       = 512
```

These values are configurable in the Master profile/config.

## CLI

Every preset receives the storage client package.

```text
storagectl ping
storagectl set <namespace> <key> <value-or-json>
storagectl get <namespace> <key>
storagectl delete <namespace> <key>
storagectl list <namespace>
```

Examples:

```text
storagectl set steamplant preferred_mode \"auto\"
storagectl set elevator last_floor 2
storagectl get elevator last_floor
storagectl list elevator
```

## Lua client

```lua
local storage = require("lib.storage_client")

local value, err = storage.get("elevator", "last_floor")
if not err then
    storage.set("elevator", "last_floor", 2)
end
```

The current client API is synchronous and intended for commands, setup tasks and
low-frequency module operations. High-frequency telemetry should continue to use
the telemetry/event transport instead of shared storage.

## Wire protocol

Requests use channel `4255`, responses use `4256`.

Requests include the logical network and are ignored by stores belonging to
another network.

Supported actions:

```text
ping
get
set
delete
list
```

The Master advertises `network.storage` through node discovery.
