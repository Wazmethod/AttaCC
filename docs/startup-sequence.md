# Black-start sequence

Create clutch semantics in this installation: **redstone ON = clutch cut**, **redstone OFF = clutch engaged**.

Physical redstone mapping on the Collector:

- `top`: MAIN clutch
- `left`: ALT clutch
- `right`: GEN clutch, connecting the electric motor/generator startup branch

Automatic/manual startup sequence:

1. MAIN cut.
2. ALT cut.
3. GEN engaged.
4. Electric motor starts at 64 RPM.
5. Wait until plant RPM reaches at least 32 RPM and remains stable for 2 seconds.
6. MAIN engaged so steam drive takes over.
7. GEN cut immediately.
8. Electric motor stopped explicitly.
9. After transfer delay, ALT engaged.
10. Electric motor stopped again as a safety action.
11. Real RPM and stress-capacity telemetry must confirm `RUNNING`.

With auto-restart armed, the current controller can retry a failed black-start up to three times for one outage.
