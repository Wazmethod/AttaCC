# Wireless channels

| Channel | Direction | Purpose |
|---:|---|---|
| 4242 | Machine app -> Master/Web | application telemetry |
| 4243 | Master -> Pocket | aggregated app/status stream |
| 4245 | Master/Pocket/Web -> machine app | module commands |
| 4246 | Machine app -> command sender | command ACK |
| 4247 | Machine app -> Master/Web | events/notifications |
| 4248 | Control clients -> nodes | node administration/reboot |
| 4249 | Nodes -> control clients | node ACK |
| 4250 | Nodes <-> network | node discovery/status |
| 4251 | Control clients -> modules | module command channel |
| 4252 | Modules -> control clients | module ACK |
| 4253 | Modules -> consumers | module telemetry |
| 4254 | Modules -> consumers | module events |
| 4255 | Storage clients -> storage host | storage request |
| 4256 | Storage host -> clients | storage response |

Commands carry IDs. Applications deduplicate retried commands where required.
