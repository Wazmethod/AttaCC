# Architecture

The project currently uses three CC:Tweaked machines.

```text
Create plant peripherals
        |
        | wired modem / peripheral network
        v
+-------------------+
| Collector         |
| role: collector   |
+-------------------+
     | telemetry 4242
     | events    4247
     | ACK       4246
     ^ control   4245
     |
     +----------------------+------------------+
                            |                  |
                    +-------v------+    +------v------+
                    | Master       |    | Pocket      |
                    | wall monitor |    | remote      |
                    +--------------+    +-------------+
                            |
                            | optional WSS
                            v
                      Hosted web POC
```

## Responsibilities

- **Collector**: reads Create peripherals, owns redstone outputs, electric motor control, plant detection and black-start state machine.
- **Master**: wall dashboard, touch controls, event history, command retries/ACK handling, Pocket status stream.
- **Pocket**: mobile status/control UI.
- **Web POC**: optional hosted dashboard and command bridge.

The Collector remains the authority for physical control.
