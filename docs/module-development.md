# Developing AttaCC modules and applications

## Reusable module

Create generic capabilities under `modules/`.

A module should do one reusable thing and avoid business decisions.

Typical API:

```lua
local M = {}

function M.read() ... end
function M.write(value) ... end

return M
```

Use `core.bus` when local event-based communication is useful.

## Machine application

Business behavior belongs under:

```text
apps/<app>/
```

A controllable app should publish telemetry with a `ui` descriptor containing
`ui.app`, `ui.groups` and `ui.controls`.

This lets Pocket, Master and Web expose the new machine without importing its
local view.

## Views

Generic display behavior belongs to `module.display`.

Application rendering belongs to files such as:

```text
view.lua
view_text.lua
view_graphics.lua
```

The main application must continue to run when no display is present.

## Package

Add the application or module to `packages/manifest.lua` and keep its package
self-contained.

A preset should normally depend on the app rather than listing the app's files
itself.
