# Wireless channels

| Channel | Direction | Purpose |
|---:|---|---|
| 4242 | Collector -> Master | telemetry |
| 4243 | Master -> Pocket | status/heartbeat stream |
| 4245 | Master/Pocket/Web bridge -> Collector | commands |
| 4246 | Collector -> command sender | command ACK |
| 4247 | Collector -> Master | events/notifications |

Commands have IDs and the Collector deduplicates retried packets for a short period.
