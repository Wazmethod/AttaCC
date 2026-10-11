# Historical machine/module notes

This document used to contain the primary architecture specification.

The canonical architecture is now documented in
[architecture.md](architecture.md) and follows:

```text
Machine -> Services -> Modules -> Logical I/O -> Peripherals
```

The historical package names `collector`, `controller`, `master` and
`pocket` remain supported as installer compatibility presets, but they must
not be treated as machine identity or application architecture.

For current documentation, use:

- [concepts/machines.md](concepts/machines.md)
- [concepts/services.md](concepts/services.md)
- [concepts/modules.md](concepts/modules.md)
- [concepts/profiles-and-io.md](concepts/profiles-and-io.md)
- [module-development.md](module-development.md)
- [operations/package-manager.md](operations/package-manager.md)
- [operations/network-storage.md](operations/network-storage.md)
