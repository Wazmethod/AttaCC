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
