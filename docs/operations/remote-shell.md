# Remote shell (legacy / optional)

The SSH-like remote shell was part of the 0.28 Unix-like runtime experiment.

It is **not installed by the standard 0.29 presets** and is not part of the
native runtime architecture.

Normal remote operation now uses explicit logical-network commands:

```text
Master / Web
   -> command packet
      -> target machine application
         -> validated action
```

This is lighter than transporting an interactive shell and keeps hardware
control inside the application which owns the machine.

The packages `module.remote-shell` and `service.remote-shell` remain in the
manifest temporarily for compatibility/testing and can still be installed
explicitly:

```text
pkgctl install service.remote-shell
```

They should not be used as a dependency for new modules or presets.

Existing SSH traffic is not real SSH and is not encrypted; this is another
reason not to use it as the primary control plane.
