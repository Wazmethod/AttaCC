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
