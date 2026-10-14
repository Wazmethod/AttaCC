# AttaCC SDK — Hello CraftOS

A tiny test app for CC:Tweaked. It demonstrates the **real** AttaCC local APIs: `lib.runtime` and `lib.bus`. It does not need an attached modem, monitor, or peripheral.

## Package creation through Web

In **Repository → Code & Import**:

1. ZIP only `main.lua` from this folder, and inspect it.
2. Target directory: `apps/sdk-hello`.
3. Type: Application, Name: `sdk-hello`, Version: `1.0.0`.
4. Dependencies: `core.runtime`.
5. Map `main.lua` to `sdk-hello.lua` on CraftOS.
6. Publish as `app.sdk-hello`.

Alternatively, the manually authored manifest entry is:

```lua
["app.sdk-hello"] = {
    kind = "app",
    version = "1.0.0",
    description = "Small event bus and runtime SDK example",
    depends = { "core.runtime" },
    files = {
        { src = "apps/sdk-hello/main.lua", dest = "sdk-hello.lua" },
    },
},
```

In that manual example, place the Lua file in `apps/sdk-hello/main.lua` and add the entry to `packages/manifest.lua`.

## Test in Minecraft

```lua
pkgctl source test
pkgctl install app.sdk-hello
sdk-hello
```

Press **P** to emit an event and watch the handler print. Press **Q** to exit, then:

```lua
logctl status
logctl tail 30 example
```

This confirms the example's state and logs. Running `pkgctl install` does **not** change the active preset. To start a new application on boot, create a custom preset from the Web editor, referencing `app.sdk-hello` and `sdk-hello.lua`, then install and activate that preset on a spare CC.

Do not add credentials, tokens, or private configuration to this example.
