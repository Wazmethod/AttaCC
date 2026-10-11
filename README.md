# steamplant-cc

Steam power plant supervision and black-start control for **CC:Tweaked + Create**.

Current development version: **0.4.0-dev**.

## Features

- Create steam plant telemetry
- wall-monitor dashboard
- Advanced Pocket Computer remote
- MAIN / GEN / ALT clutch control
- electric motor black-start procedure
- armed automatic restart with physical RUNNING verification and retry handling
- reliable command IDs, ACKs and retries
- Master debug page and event log
- optional hosted web dashboard POC over an outbound WebSocket

## Repository layout

```text
cc/
  collector/   plant I/O, telemetry and startup controller
  master/      wall dashboard and command station
  pocket/      handheld remote
web/           Docker/WebSocket dashboard POC
docs/          architecture and installation notes
install.lua    in-game GitHub installer/updater
version.json   project version metadata
```

## Quick in-game install

The repository is currently private, so the installer requires a **fine-grained GitHub PAT** scoped only to this repository with **Contents: Read-only**.

On each CC computer, first download `install.lua`. For a private repository, the easiest first bootstrap is to paste `install.lua` once into the computer, or temporarily use a public/raw location. After that, the installer can update all role files through the GitHub API.

Run:

```text
install
reboot
```

Default role mapping:

```text
ID 0 -> collector
ID 1 -> master
ID 2 -> pocket
```

See [docs/installation.md](docs/installation.md) for wiring and dependencies.

## Wireless protocol

See [docs/channels.md](docs/channels.md).

## Black start

See [docs/startup-sequence.md](docs/startup-sequence.md).

## Web POC

```bash
cd web
cp .env.example .env
nano .env
docker compose up -d --build
```

Then configure `web/cc/webbridge.lua` with the hosted WebSocket URL and machine token.

## Security

Do not commit GitHub PATs, web admin tokens, machine tokens or other secrets. Local token/config files are ignored by `.gitignore`.
