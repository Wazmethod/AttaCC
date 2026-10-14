# AttaCC applications

This directory contains machine/application-specific behavior.

A quick look inside an application should explain most of what the corresponding
CC computer does.

## Convention

```text
apps/<app>/
  main.lua          orchestration and event loop
  config.lua        default application configuration
  machine.lua       machine identity/profile integration
  controller.lua    app-specific state machine, when applicable
  telemetry.lua     business data publication, when applicable
  io.lua            application-specific I/O mapping, when applicable
  view.lua          application display adapter
  view_text.lua     text business view
  view_graphics.lua CC:Graphics business view
  tools/            application-specific maintenance commands
```

Not every application needs every file.

Generic capabilities do not belong here:

```text
core/       minimal AttaCC runtime and local bus
modules/    reusable capabilities such as network, display and storage
apps/       machine/application business behavior
```

A controllable machine application publishes its UI/control descriptor through
telemetry. Master, Pocket and Web consume that descriptor independently of the
application's local monitor view.
