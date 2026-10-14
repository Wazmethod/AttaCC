# Machines, applications and modules

The current AttaCC relationship is:

```text
Machine
  -> Application
      -> Core runtime
      -> Reusable modules
      -> Application-specific I/O
      -> Peripherals
```

A machine advertises its applications, modules, capabilities, topology and
runtime state through network discovery.

For a new technical machine, start with an `apps/<name>/` application and add
only the reusable modules it needs.
