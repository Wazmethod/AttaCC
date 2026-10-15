// English-language operational documentation and command manuals bundled for offline WebUI.
export const referencePages = [
  {
    "id": "guide-intro",
    "title": "Operations · Overview",
    "type": "guide",
    "text": "# AttaCC Operations Guide\n\nAttaCC runs on CC:Tweaked. Each computer has a stable machine identity, a boot preset, installed packages and optional peripherals. Use **machinectl**, **profilectl**, **ioctl**, **pkgctl** and **logctl** to administer the local machine. The WebUI provides fleet discovery, machine status and a package repository. This page is an operational reference, not evidence of complete in-game testing."
  },
  {
    "id": "guide-1",
    "title": "Architecture & Responsibilities",
    "type": "guide",
    "text": "# Architecture and Responsibilities\n\n```text\nCraftOS startup.lua → /etc/preset → application\ncore/                 → identity, discovery, runtime, local bus, protocol\nmodules/              → reusable network, display, storage and I/O\napps/                 → SteamPlant, Master, Pocket, Workstation, Dashboard\npkgctl.lua            → package installation, updates and dependency resolution\nWebBridge              → Master ↔ AttaCC Web\n```\n\n**SteamPlant** controls its generator, **Master** aggregates and routes, **Pocket** is a portable client, **Workstation** provides operator tools, and **Dashboard** offers a dedicated display. A Storage host is an independent capability, not a requirement for Master."
  },
  {
    "id": "guide-2",
    "title": "Installation & Updates",
    "type": "guide",
    "text": "# Installation and Updates\n\nUse the Web Repository configured in your Minecraft instance:\n```lua\nwget http://HOST:8080/repo/install.lua install\ninstall\npkgctl source show\npkgctl source test\npkgctl status\npkgctl update\n```\n\nFor an existing machine, verify the source before updating. `pkgctl install` installs a package and its dependencies. `pkgctl activate preset.example` changes the boot preset of an already installed custom preset. Restart after switching presets. The managed Web Repository persists independently of the Docker Git checkout; back up custom packages before importing Git."
  },
  {
    "id": "guide-3",
    "title": "Storage Clients & Hosts",
    "type": "guide",
    "text": "# Storage\n\nAttaCC Storage separates a **client** (`module.storage-client`) from a **host** (`module.storage-server`). Clients explicitly select a host and namespace with `storagectl use` and can inspect the target using `storagectl target`. Hosts are configured and maintained with `storagehostctl`. Keep independent backups and pause writes during data migration; moving storage is not a database merge.\n\nSee the **storagectl** and **storagehostctl** command manuals for procedures."
  },
  {
    "id": "guide-4",
    "title": "Identity & Profiles",
    "type": "guide",
    "text": "# Machine Identity and Profiles\n\n`/etc/machine.lua` stores logical machine identity; `/etc/profile.lua` stores profile settings. Local app settings and I/O mappings have their own configuration. Use `machinectl status` to inspect the hostname and machine key, `machinectl init` to configure them, and `profilectl` to inspect or synchronize configuration. Machine keys must be unique; importing the same identity on two online CCs can create a conflict. Restart after identity/network changes where necessary."
  },
  {
    "id": "guide-5",
    "title": "Displays & Peripherals",
    "type": "guide",
    "text": "# Displays and Peripherals\n\n`module.display` provides display-related capabilities independently from app-specific screens. Missing displays must not automatically stop an application that treats them as optional. Pocket and standard/Advanced computers offer different terminal capabilities. Use `ioctl hardware` and `ioctl check` when an app depends on monitor, sensor, redstone or modem bindings."
  },
  {
    "id": "guide-6",
    "title": "Logs & Diagnostics",
    "type": "guide",
    "text": "# Logs and Diagnostics\n\n```lua\nlogctl\nlogctl status\nlogctl tail 30\nlogctl errors 30\nlogctl tail 20 app:workstation\npkgctl status\nmachinectl status\n```\n\nLocal component statuses are reported by apps and the startup runtime; a displayed `ready` does not continuously supervise the process. Local journals use bounded rotation. Machine version is the installed `core.runtime` package version, not a stale legacy `version.json` file."
  },
  {
    "id": "guide-7",
    "title": "Web & Security",
    "type": "guide",
    "text": "# Web and Security\n\nAttaCC Web runs as a Docker Node service. Browsers consume state and submit declared actions; WebBridge connects the Minecraft network to the backend. Configure separate strong `ADMIN_TOKEN` and `MACHINE_TOKEN`; placeholder tokens are rejected. Admin APIs require authorization. The public package endpoint `/repo` must not expose hidden paths. Protocol message shape validation by itself is **not authentication**. Protect secrets and back up `web/data`."
  },
  {
    "id": "guide-8",
    "title": "Troubleshooting",
    "type": "guide",
    "text": "# Troubleshooting\n\n1. Verify Docker is running and `/repo/packages/manifest.lua` serves the expected revision.\n2. Check `pkgctl source test` on the failing CC.\n3. Check `pkgctl status` for missing binaries and dependency versions.\n4. Run `logctl errors` and `logctl status`.\n5. Inspect the active preset in `/etc/preset`, installed peripheral bindings, machine identity, and local network.\n6. Reproduce on a spare computer before changing the Master or SteamPlant machine.\n\nIf Git changes don't appear in CraftOS, the managed Web Repository may be stale. A container rebuild does not necessarily update its files."
  },
  {
    "id": "tests-intro",
    "title": "Validation · Overview",
    "type": "tests",
    "text": "# Release Validation\n\nTesting a Docker start and two CC computers verifies basic deployment, not every failure path. Use a separate test Web Repository and spare computers for destructive tests. Validate standard and Advanced computers, package import/update/delete, startup of native and custom presets, WebBridge and logs. Record actual commands, expected behavior and errors before a release."
  },
  {
    "id": "tests-1",
    "title": "Validation · Checklist",
    "type": "tests",
    "text": "# Release Acceptance Checklist\n\n- [ ] Docker build/start with configured non-default tokens\n- [ ] Public `/repo` manifest and installer readable\n- [ ] Hidden files under `/repo` blocked\n- [ ] Fresh install on Advanced Computer\n- [ ] Fresh install on normal Computer\n- [ ] Native preset boots successfully\n- [ ] Custom preset installs, activates, boots\n- [ ] Create/update/remove custom package with dependencies\n- [ ] Offline/failed download leaves existing package intact\n- [ ] `pkgctl status` and `logctl status/errors/tail` work\n- [ ] Machine identity/version is reported correctly\n- [ ] Master/WebBridge connectivity and authorized Web actions work\n- [ ] Repository backup and restore rehearsed on a copy\n\nDo not treat these boxes as automatically certified. Check them during actual validation."
  },
  {
    "id": "audit-intro",
    "title": "Audit · Overview",
    "type": "audit",
    "text": "# Technical Review\n\nSource-level findings do not prove in-game behavior. Critical priorities include authentication, preserving custom packages, correct package version reporting, safe repository paths, and reliable startup. CraftOS lacks a full crash-proof package transaction. Keep its limits documented and favor small, testable fixes over speculative rewrites."
  },
  {
    "id": "audit-1",
    "title": "Audit · Known Limitations",
    "type": "audit",
    "text": "# Known Limitations\n\n- `pkgctl` downloads a package before replacing that package's files and attempts rollback on handled write errors. Power loss or an abrupt Minecraft shutdown during writes is **not** crash-safe.\n- Web's managed repository under `web/data` is independent from the Git checkout.\n- Package metadata and the legacy repository custom registry can disagree for older imported packages.\n- Custom package manifest updates use generated-block text parsing and should be tested after manual edits.\n- `core.protocol.validateCommand` checks shape and freshness but is **not** sender authentication.\n- Some legacy docs and deployment paths can be historical; prefer current CLI and release notes."
  },
  {
    "id": "man-logctl",
    "title": "logctl",
    "type": "man",
    "text": "# logctl(1) — Local Diagnostics\n\n## SYNOPSIS\n```text\nlogctl\nlogctl status\nlogctl tail [n] [component]\nlogctl errors [n] [component]\nlogctl help\n```\n\n## DESCRIPTION\nWith no arguments, `logctl` displays its help. `status` prints reported component statuses; `tail` displays recent local log messages (default 30); `errors` shows warnings and errors. `health` is a deprecated alias for `status`.\n\n## EXAMPLES\n```lua\nlogctl status\nlogctl tail 50\nlogctl errors 20 app:workstation\n```\n\n## NOTES\nTerminal colors depend on CraftOS computer type. State is declarative rather than a process heartbeat. Logs are stored locally with rotation. Installed by `core.runtime`."
  },
  {
    "id": "man-machinectl",
    "title": "machinectl",
    "type": "man",
    "text": "# machinectl(1) — Machine Identity\n\n```text\nmachinectl status\nmachinectl init\nmachinectl hostname [new-hostname]\nmachinectl export [file]\nmachinectl import [migration-code]\nmachinectl reset\n```\n\n`status` displays identity, role, hostname, apps/modules, network, computer ID and the installed `core.runtime` version. `init` prompts for identity fields. `hostname` reads or modifies the hostname. `export` creates an `IM1-` migration code, `import` restores it, and `reset` removes local identity after confirmation.\n\nMachine keys must be unique. Identity changes may require a restart. Identity is stored under `/etc/machine.lua`."
  },
  {
    "id": "man-pkgctl",
    "title": "pkgctl",
    "type": "man",
    "text": "# pkgctl(1) — Package Manager\n\n```text\npkgctl list\npkgctl status\npkgctl show <package>\npkgctl deps <package>\npkgctl install <package>\npkgctl update [package]\npkgctl upgrade [package]\npkgctl configure <package>\npkgctl activate <custom-preset>\npkgctl prune\npkgctl source show\npkgctl source set http://HOST:8080/repo\npkgctl source test\npkgctl source github\n```\n\nPackages are defined by a manifest with versions, file mappings and dependencies. `source` selects or tests the Web Repository or resets to GitHub fallback. `install` resolves dependencies. `update` replaces installed files; `status` shows installed versions and missing files. `activate` selects an installed **custom** boot preset. `prune` removes packages outside the explicit dependency roots; inspect the status first.\n\n`pkgctl` cannot guarantee recovery after a hard crash during a file replacement. Back up important local state before risky updates."
  },
  {
    "id": "man-storagectl",
    "title": "storagectl",
    "type": "man",
    "text": "# storagectl(1) — Storage Client\n\n```text\nstoragectl init\nstoragectl hosts\nstoragectl use <machine-key> [namespace]\nstoragectl target\nstoragectl ping\nstoragectl ns\nstoragectl tree\nstoragectl list <namespace>\nstoragectl get <namespace> <key>\nstoragectl set <namespace> <key> <value|json>\nstoragectl delete <namespace> <key>\n```\n\nSelect the intended Storage host explicitly with `storagectl use`; `target` displays the selected host and namespace. Client operations require a selected host. `get`, `set`, `list` and `delete` access stored keys. The host's persistent machine key is used rather than its display label."
  },
  {
    "id": "man-storagehostctl",
    "title": "storagehostctl",
    "type": "man",
    "text": "# storagehostctl(1) — Storage Host Administration\n\n```text\nstoragehostctl status\nstoragehostctl configure\nstoragehostctl backup [path]\nstoragehostctl migrate local\nstoragehostctl migrate drive\n```\n\nOnly installed with `module.storage-server`. Inspect backend status, configure storage, perform a backup, or migrate between local storage and a labelled data disk. Migration is not a merge operation. Stop client writes and validate backups before moving data."
  },
  {
    "id": "man-profilectl",
    "title": "profilectl",
    "type": "man",
    "text": "# profilectl(1) — Profiles and Synchronization\n\n```text\nprofilectl\nprofilectl show\nprofilectl status\nprofilectl edit\nprofilectl init\nprofilectl push\nprofilectl pull\nprofilectl machines\nprofilectl edit remote <machine-key> [profile|machine]\nprofilectl storage-sync\nprofilectl reset\n```\n\nReads or edits local machine/profile settings and synchronizes them with a selected Storage host. `push` publishes local configuration; `pull` replaces local configuration with its stored copy. Check your Storage target and back up first. Use `machinectl` for logical identity and `ioctl` for peripheral bindings."
  },
  {
    "id": "man-ioctl",
    "title": "ioctl",
    "type": "man",
    "text": "# ioctl(1) — Hardware and I/O Configuration\n\n```text\nioctl init\nioctl check\nioctl hardware\n```\n\n`init` assists with machine I/O configuration; `check` validates declared hardware requirements against connected devices; `hardware` lists detected peripherals. The I/O registry exposes `read` and `write` only for configured bindings. Check the on-device `ioctl` help for additional subcommands supported by the installed release."
  },
  {
    "id": "man-webbridgectl",
    "title": "webbridgectl",
    "type": "man",
    "text": "# webbridgectl(1) — WebBridge Configuration\n\nWebBridge connects the Master to AttaCC Web. Use `webbridgectl` on the Master to inspect available subcommands and configure the Web endpoint and authentication. Keep the machine token consistent with the Docker backend. Do not publish the token in logs, screenshots or Git repositories."
  }
];
