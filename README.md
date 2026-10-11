# CC Infrastructure Control

Modular infrastructure supervision and control network for **CC:Tweaked**.

The Create steam plant is the first production module, not the final scope of the project.

Current development version: **0.18.0-dev**.

## Features

- Create steam plant telemetry
- wall-monitor dashboard
- collector-local monitor dashboard with touch controls
- Advanced Pocket Computer remote
- MAIN / GEN / ALT clutch control
- electric motor black-start procedure
- armed automatic restart with physical RUNNING verification and retry handling
- reliable command IDs, ACKs and retries
- Master debug page and event log
- optional hosted web dashboard POC over an outbound WebSocket

## Architecture

The network is organized by physical **machine**, with one or more logical
**modules** advertised by each machine. See
[docs/machine-modules.md](docs/machine-modules.md).

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

Production machines use persistent logical identities independent from the
CC:Tweaked computer ID. This makes reinstalling or replacing hardware safe:

```text
machinectl status
machinectl export
machinectl import <migration-code>
```

See [docs/installation.md](docs/installation.md) for wiring, identity setup and
migration.

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

## Hosted dashboard

See [docs/dashboard.md](docs/dashboard.md).


## Per-machine profiles

Installed roles are reusable runtimes. Machine-specific modules, peripheral
bindings and dashboards live in `profile.local.lua` and can be configured with
`profilectl init`. Identity/network settings remain in `machine.local.lua`.
