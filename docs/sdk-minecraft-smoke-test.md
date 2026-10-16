# First safe Minecraft SDK smoke test

Use a **new isolated CC:Tweaked computer**, not the active SteamPlant controller. This is a **preview smoke test**, not production cutover.

## Bootstrap from the SDK branch

In CraftOS, on a fresh computer with HTTP enabled:

```text
wget https://raw.githubusercontent.com/Wazmethod/AttaCC/feature/v1.1-sdk-unification/pkgctl.lua pkgctl.lua
pkgctl source branch feature/v1.1-sdk-unification
pkgctl source show
pkgctl source test
pkgctl install app.master-sdk-preview
```

The branch setting persists in `/etc/pkgctl/branch`. Never run this test procedure on your production CC machines. If you already use a configured HTTP mirror via `pkgctl source set`, that mirror takes precedence over the GitHub branch. Switch to GitHub with `pkgctl source github` only on the isolated test computer.

Install the **Pocket preview** on a second separate test computer:

```text
pkgctl install app.pocket-sdk-preview
```

For SteamPlant use the existing `docs/steamplant-first-sdk-test.md` hardware-safe procedure. **Do not start a real generator yet.** Configuration of unique signed peers is required before snapshots/announcements appear; unsigned traffic is intentionally ignored.

## First acceptance stage

1. Verify `pkgctl source show` prints the SDK branch and that `pkgctl source test` can read its manifest.
2. Confirm the preview packages install their declared dependencies and do not change the existing presets.
3. Run `appctl check master_preview`, then `appctl master_preview` on the test computer; test terminal rendering.
4. On the Pocket preview test computer, run `appctl check pocket_preview`, then `appctl pocket_preview`.
5. After provisioning `/etc/sdk-auth.lua` on each computer (see `docs/sdk-network-authentication.md` and `docs/sdk-v11-cutover.md`), confirm authenticated discovery and telemetry. Keep all remote controls disabled.
6. Report any startup error, layout issue and monitor size. Do not publish authentication keys.

## Important limitations

Master/Pocket/Workstation visual parity and WebBridge server interoperability remain unfinished. This sequence is for early non-destructive functionality only. Until the exact branch passes GitHub CI and the tests above run inside Minecraft, the SDK is not certified for live operation.

## Pocket preview display update

The SDK Pocket preview now renders application views directly on its own
screen instead of using the maintenance-only console. It uses CC:Graphics
when supported, otherwise the SDK text renderer. The Master and other
standard computers retain their independent text maintenance console.

After updating your Docker mirror, stop Pocket Preview, then run:

```text
pkgctl update core.runtime
pkgctl update app.pocket_preview
appctl pocket_preview
```

This is a gameplay test candidate: verify HOME/DATA/CONTROLS navigation,
Pocket touch coordinates, small display fallback, and whether SteamPlant
telemetry appears. Keep remote actions disabled. The layout is still a
generic SDK design, not final visual parity with the historical Pocket UI.

## Shared CC:Graphics layout iteration

The generic `lib.display_sdk_graphics` renderer now presents action widgets in
a compact toolbar rather than oversized cards. Applications declare their
own view widgets/order and optionally `columns` (1–4) and `cardHeight`
(pixels) through `app:view(id,{...})`. The SDK library owns drawing, sizing,
navigation hitboxes and backend selection: there is no Master-only or
Pocket-only drawing engine.

For a live visual test, stop the affected SDK apps, refresh your Docker mirror
from `feature/v1.1-sdk-unification`, then on each CC run:

```text
pkgctl update core.runtime
pkgctl update module.display
pkgctl update app.master_preview
```

On Pocket replace the last command with `pkgctl update app.pocket_preview`.
Restart with `appctl master_preview` / `appctl pocket_preview` respectively.
Validate tabs, compact action toolbar, page navigation, graphics touch and
CraftOS terminal fallback before enabling any remote command. Graphic output
is not yet hardware-verified for this renderer iteration.

## Shared grouped-widget rendering test

The SDK graphical renderer now supports app-defined `{type="group",label=...,items={...}}` widgets: one card contains multiple exported data fields. Apps choose the groups, source fields, actions and order. `module.display` owns sizing, automatic content pagination and nav arrows. Master and Pocket now use the same grouped rendering primitives. The DATA and CONTROLS tabs page through their source exports via app-owned controls. Count values show no artificial `.00` suffix when integral.

On the Docker host update `feature/v1.1-sdk-unification`. Stop the preview app before updating these packages on Master and Pocket:

```text
pkgctl update core.runtime
pkgctl update module.display
pkgctl update app.master_preview
```

Use `pkgctl update app.pocket_preview` instead of Master's app package on Pocket, then launch the preview again. Check large/small screen pagination, source switching, the grouped export lists and touch navigation. This renderer iteration is still awaiting an in-game screenshot check.

## Shared two-row navigation contract

In CC:Graphics, `module.display` owns the same layout for Pocket and Master:
top strip = view/subcategory tabs plus content paging arrows;
second strip = previous source, selected application, next source
(only where `sourceNavigation` is declared); then the app's grouped
export widgets. Main category tabs stay at the bottom. Pager/source control
IDs declared by an app are not repeated as big content actions, even when
they also appear in an older `widgets` list.

**Important:** Pocket's `app.pocket_preview` update alone cannot install
changes to the shared renderer. After synchronizing the Docker repository,
stop the preview and update **both** `module.display` and
`app.pocket_preview`. Update `core.runtime` if it has not been updated
since the parent `sourceNavigation` feature was added. Launch the Pocket
preview and check top arrows, source row and touch hitboxes before enabling
remote controls.

## Pocket exported graphs and centered headings

The native Pocket candidate declares a DATA child view named GRAPHS and renders two remote graph exports per page. Incoming graph samples are cached for the selected source; selecting another source resets the rendered series. The shared graphics renderer centers the active category title at the top and moves the text-mode switch to the right. Source selection remains on the second line.

Stop the running preview, refresh the Docker repository, then update `module.display`, `core.runtime` (only if behind) and `app.pocket_preview`. Validate graph samples, page arrows, source switching and touch targets in Minecraft. Remote commands stay disabled by default.

## Pocket V1.1 default on a new computer

The `preset.pocket` package now installs SDK-native `app.pocket` in
`apps/pocket/main.lua`. The legacy multi-file Pocket app is not installed
by this preset. On an **empty** Pocket Computer point `pkgctl` at the existing
Docker HTTP repository, run `pkgctl source test`, then:

```text
pkgctl install preset.pocket
appctl check pocket
appctl pocket
```

The application has HOME (network counts, Master and future Storage status),
MACHINE with DATA, GRAPHS, CONTROLS and MACHINES subcategories, and EVENTS
with a separate machine filter. Changing the MACHINE selection does not
change the EVENTS filter. The native SDK display owns screen rendering and
touch targets.

Remote controls and reboot are disabled by default. REBOOT only becomes
available with explicit Pocket remote permission **and** an online node-agent
application able to accept signed `node_reboot` with `confirm=true`. The
node-agent and per-peer authorization must be deliberately enabled on the
remote machine; do not test reboot on active SteamPlant hardware without
first confirming safe shutdown behavior.

Events are consumed through a wildcard SDK event subscription, excluding
routine `node.status` announcements. Existing non-SDK/legacy events are not
automatically translated. Data/graphs are read from the selected machine's
selected SDK application. With multiple applications on one machine, the
current version defaults to the first application by key; app selection
inside that machine is a future refinement.

This branch is tested in Minecraft manually: no GitHub Actions CI is used.

## Migrating installed Master from legacy to SDK

On the Docker HTTP mirror, pull the dedicated SDK branch. Stop any running
legacy Master and master_preview instances on the in-game computer. Then:

```text
pkgctl update runtime.package-manager
pkgctl update core.runtime
pkgctl update module.display
pkgctl update app.master
pkgctl activate preset.master
reboot
```

For a completely fresh Master, install `preset.master` and activate it.
The SDK Master now has app id `master`; previously installed legacy files
may remain on already-used computers, but the preset launches
`apps/master/main.lua`, which is SDK-native. Master defaults to launching
in a separate multishell tab. Configuration of machine identity and network
remains in `/etc/machine.lua`; Pocket and Master must share the same network
for discovery. The native Master UI is still the former preview feature set:
do not assume legacy WebBridge/storage feature parity.

## Native node administration and categorized exports

The runtime now registers `node_reboot`, `node_package_update`, and
`node_package_configure` on every SDK application through
`lib.sdk_node_admin`. A separate node-agent process is no longer needed
for these actions. These commands are **disabled by default**, and remain
subject to the destination's signed command ACL and confirmation checks.
To opt a machine in, create or edit
`/etc/attacc/apps/<app-id>/config.lua` with the application's existing
configuration plus:

```lua
admin = {
    enabled = true,
    actions = {
        reboot = true,
        package_update = false,
        package_configure = false,
    },
},
```

Enable corresponding signed-client policy on Pocket and signed peer
authorization on the destination before attempting remote administration.
Never enable remote reboot on an actively controlled SteamPlant without a
safe shutdown policy. Existing `node_agent` is retained for compatibility
but is no longer required by native apps.

Applications can now supply `category` to
`app:data(id, {label=..., category="..."} )`,
`app:graph(id, {..., category="..."} )`, and
`app:control(id, {..., category="..."} )`.
The SDK carries these categories through `app:descriptor()` and wireless
snapshots. Pocket pages exports without mixing category boundaries; DATA
shows its category, and GRAPHS/CONTROLS include the category in their
labels. Categories default to `general` for older exports.

## SDK export value normalization

Category-less SDK exports are displayed under `UNCATEGORIZED` in the shared
CC:Graphics renderer. Boolean values are shown as colored `ON`/`OFF` text.
Finite numeric telemetry and the latest graph sample are rounded to two
decimal places when serialized in `sdk_snapshot.frame`; internal source
application values and control logic retain full precision. Rendering drops
trailing zeroes (`100`, `8.42`, `10.7`), without modifying units or
string exports. Packet consumers needing higher precision should use a
separate transport/field rather than depending on rounded display telemetry.

Update `core.runtime` on the data publisher (e.g. SteamPlant), and
`module.display` on Master and Pocket. Stop the source controller in a safe
state before updating it; verify boolean labels and telemetry after restarting.

## State-aware exports and direct Pocket controls

An SDK application owns boolean presentation for its exported data:

```lua
app:data("main_clutch",{label="Main clutch",category="Transmission",
    trueLabel="ENGAGED",falseLabel="DISENGAGED"})
```

The application can also declare the button caption and target action for
each control state. State-aware buttons are described by the source app, while
Pocket renders them; Pocket does not receive executable Lua.

```lua
app:control("clutch_toggle",{
    label="Clutch",category="Transmission",remote=true,confirm=true,
    state=function() return mainClutchEngaged end,
    trueLabel="DISENGAGE",falseLabel="ENGAGE",
    trueControl="clutch_disengage",falseControl="clutch_engage",
    run=function() return false,"use explicit guarded clutch actions" end
})
```

The state-specific targets must themselves be enabled, exported remote controls
on the same application. Every remote call still requires configured signed
authorization; the SDK never enables it just because the button is visible.
The Pocket control page now uses direct per-export buttons in category cards
rather than a generic EXECUTE selector. Pages and navigation arrows come from
the common renderer; page count appears in the selected subcategory tab when
multiple pages exist, and unused paging arrows are hidden.

This requires `core.runtime` on the publisher and the Pocket, plus
`module.display` and `app.pocket` on the Pocket. Perform a Minecraft tactile
smoke test before enabling any action on production machinery.

## SteamPlant typed export groups and chart axes

SteamPlant now owns categories for Generator, Boiler, Energy, Motor,
Status, Clutches, Automation, and its safety/command actions.
Boolean telemetry exports can carry source-defined status text such as
ENGAGED/DISENGAGED and ARMED/DISARMED.

Graph declarations support `min`, `max`, `resolution` and
`timeWindow`. `resolution` specifies **time-axis grid spacing in seconds**,
not sampling frequency or numerical precision. `timeWindow` is the graph's
visible history in seconds. Both values are sent in SDK snapshots and
passed to the common renderer by Pocket and Master.

For percent graphs (Accumulator, Mechanical load, Boiler water/heat)
SteamPlant uses `min=0,max=100,resolution=30,timeWindow=120`.
RPM charts remain auto-ranging because their valid hardware range depends
on the connected machinery. The horizontal timeline is relative to the
last received sample, using millisecond timestamps and second labels
(e.g. -120s, -90s, -60s, -30s, 0s). No wall-clock assumptions.

Update `core.runtime` on SteamPlant, Pocket and Master;
`app.steamplant` on SteamPlant; `module.display` on Pocket/Master/SteamPlant;
and `app.pocket`/`app.master` on their respective computers if behind.
Test on stopped/secured hardware before returning SteamPlant to service.
No in-game validation has been performed automatically.

## Pocket: machine-first tabs, adaptive graph grids, signed SteamPlant controls

Pocket's MACHINE root is now the MACHINES list, followed by DATA, GRAPHS
and CONTROLS. The shared CC:Graphics renderer can draw up to 2x2 graphs
on a sufficiently large screen; smaller screens keep fewer graphs per page.
A page never mixes different source-defined graph categories. No legacy
Master or SteamPlant drawing paths are reintroduced.

Pocket's built-in remote controls switch is enabled, but buttons remain
locked until local `/etc/sdk-auth.lua` contains an enabled signed client
with `client.origin` exactly equal to Pocket's logical
`/etc/machine.lua` key, and a private secret of at least 32 characters.
SteamPlant must have a matching enabled entry in its own
`/etc/sdk-auth.lua` `peers` table with the same secret and an explicit
per-command `controls` allowlist. Never commit or transport these secrets
through the HTTP package repository. Follow
`docs/sdk-network-authentication.md`. The Pocket also checks selected
source freshness and confirms physical controls before sending.

For initial testing, allowlist only a single deliberately selected command
on a safe test setup. Do not enable unrestricted clutch, boiler, motor or
automatic-start operations on running equipment. Signed ACK must arrive
before reporting success. Node reboot remains a separate opt-in
administrative control.
