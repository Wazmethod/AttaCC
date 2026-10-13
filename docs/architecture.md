# AttaCC architecture

## Principles

AttaCC is intentionally small and native to CC:Tweaked.

```text
APP = why the machine does something
MODULE = reusable capability used to do it
CORE = common runtime needed by every machine
```

Business decisions stay in `apps/`. Generic hardware/network/display behavior
stays in `modules/`.

## Core

`core.runtime` installs the common primitives:

- local event bus;
- machine identity;
- network discovery state;
- protocol helpers;
- runtime state and logging;
- node administration;
- Web/system snapshot helpers;
- startup bootstrap.

Runtime state uses `app:`, `module:` and `capability:` namespaces and is
stored in `/run/attacc/state.json`.

## Local bus

`core.bus` uses CraftOS events:

```text
app -> bus -> module
module -> bus -> app
network -> bus -> app
app -> bus -> network -> remote machine
```

The bus is local by default. `module.network` controls what crosses the modem.

## Applications

Each application owns its machine-specific behavior. Typical files are:

```text
apps/<app>/
  main.lua
  config.lua
  controller.lua
  telemetry.lua
  io.lua
  view.lua
  view_text.lua
  view_graphics.lua
  tools/
```

Not every app needs every file.

Application packages are self-contained. Presets are only thin bundles selecting
an app.

## Controllable machines

A technical machine such as a generator, elevator or production line publishes
a generic control descriptor in telemetry:

```text
ui.app
  id
  title
  machine
  machineLabel
  module
  kind

ui.groups
  logical metric groups

ui.controls
  actions associated with a group
```

Master aggregates these applications. Pocket and Web consume the same
descriptor and build their own UI. They never reuse the machine's local monitor
view.

Commands include both a module and a target machine.

## Display

`module.display` is common to all apps and handles:

- monitor discovery;
- geometry;
- resize detection;
- pagination/layout helpers;
- display availability.

The actual business view belongs to the app.

A missing monitor is an inactive optional capability, never a fatal condition.

## Network discovery

Nodes advertise:

```text
identity
preset
apps
modules
capabilities
runtime state
packages/system snapshot
```

Discovery, telemetry, events, commands and acknowledgements use the AttaCC
network protocol.

## Storage

Storage is optional and package-driven:

```text
module.storage-client
module.storage-server
```

The backend is role-agnostic. A machine hosts storage only when
`module.storage-server` is installed.

## Local application UI

Interactive applications keep a lightweight local maintenance UI for status,
quick actions and recent events.

External monitors are separate business displays.

Pocket is the exception only in presentation: its built-in screen is the
application UI itself and therefore runs in the primary terminal.

## Web bridge

The Master Web bridge forwards node discovery, telemetry, events and commands
between the logical CC network and the hosted Web control plane.

Remote administration is restricted to explicit AttaCC actions such as package
updates/configuration and reboot.


## Master control display

The Master monitor is generated from discovered controllable applications.

Top-level pages:

```text
HOME
MACHINE
EVENTS
NETWORK
```

`MACHINE` selects a discovered controllable app and exposes generic subpages:

```text
DATA
GRAPHS
CONTROLS
```

Data and controls come from the app UI descriptor. Numeric graph series come
from `ui.graphs`, with numeric metrics used as a fallback. The Master therefore
does not contain SteamPlant-specific control code.

Events aggregate all machine events and include the originating hostname.
Network is built from node discovery.

The HOME widgets are configured with:

```text
profilectl home
```

The local Master application exposes a Home Config button which opens this
assistant.

## Removable storage media

`module.storage-server` supports three backend modes:

```text
local
drive
auto
```

A Drive backend uses a CC:Tweaked data disk labelled `ATTACC_STORAGE` by
default. The store is written below:

```text
<disk mount>/attacc/storage/store.json
```

If the selected media is removed, storage becomes degraded and does not silently
switch to another store. Reinsert the expected media to recover.
