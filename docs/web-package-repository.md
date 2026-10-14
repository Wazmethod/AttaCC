# AttaCC Web Package Repository

Feature branch: `feature/web-package-repository`, based on `dev`.

## Goal

Host a deployable **package mirror** inside the existing AttaCC Web container. GitHub remains the developer repository; CC:Tweaked machines download the package manifest and its file payloads through the AttaCC Web origin.

## Initial Docker implementation

The web server exposes:

- `GET /api/repository/status` – reports whether `packages/manifest.lua` exists in the mounted checkout.
- `GET /repo/packages/manifest.lua` – provides the package manifest.
- `GET /repo/<relative-path>` – provides a file from the mounted checkout.

A directory mount `ATTACC_REPOSITORY_PATH` (default `../` relative to `web/docker-compose.yml`) maps to `/repo:ro`. The checkout should be updated by the deployment system, **not by untrusted client requests**. No write API is exposed yet. For production deployments, pin a stable tested revision/tag instead of updating the live source during client installs.

On the Docker host, in `web/`:

```sh
cp .env.example .env
# Set MACHINE_TOKEN, ADMIN_TOKEN and ATTACC_REPOSITORY_PUBLIC_URL.
docker compose up -d --build
curl http://localhost:8080/api/repository/status
curl http://localhost:8080/repo/packages/manifest.lua
```

Current `pkgctl` and `install` **still use GitHub**. This is only a backend serving foundation, **not a completed migration**.

## Planned next milestones

1. Add `/etc/pkgctl/source.lua` or equivalent persistent repo source config, retaining GitHub fallback during migration; support `pkgctl source show/set/test`.
2. Add bootstrap installation through `<public-origin>/repo/install.lua` that automatically persists the same base URL for `pkgctl`.
3. Add authenticated Web settings for publicly advertised base URL, checkout update and pinned release/channel (`stable`, `dev`). Never expose admin or Git credentials to CC clients.
4. Provide an explicit fetch/sync job in the Web backend to update the checkout from a permitted configured Git origin, stage and validate the manifest/files and atomically activate a release, rather than modifying a served tree in place.
5. Display active version, package count, last sync, last failure, repository URL and buttons for staging/promoting/rollback in a responsive Web administration panel.
6. Ensure URL rewriting works behind Traefik, HTTP(S)/WebSocket configuration remains independent, auth for administrative operations, and controlled cache-busting for `pkgctl`.

## Safety / tests before merging

- Reject traversals and symlink escapes from `/repo` (the mount is currently trusted read-only; full path hardening remains).
- Validate a repo root has `packages/manifest.lua` and all referenced files before advertising readiness.
- Test installation and update without any GitHub access from a CC.
- Test malformed manifests, interrupted publication, rollback, cache invalidation and unavailable repository.
- Validate HTTP(S) allowlists in the CC:Tweaked server config and the new source switching flow.


## Feature-branch installation and test

**Branch:** \`feature/web-package-repository\` (do not merge to \`dev\` until tested).

From the repository checkout on the Docker host:

\`\`\`sh
git fetch origin
git switch feature/web-package-repository
git pull --ff-only origin feature/web-package-repository
cd web
cp -n .env.example .env
# Set MACHINE_TOKEN, ADMIN_TOKEN, ATTACC_REPOSITORY_PUBLIC_URL
docker compose up -d --build --force-recreate
docker compose logs --tail=100
curl -f http://localhost:8080/api/health
curl -f http://localhost:8080/api/repository/status
\`\`\`

Open the WebUI **REPOSITORY** tab, provide the admin token in the normal administrative controls, set the Git URL, branch/tag, and public package URL, then **SAVE SETTINGS** and **SYNC & PUBLISH**. The backend clones a shallow checkout into staging, checks required files from the manifest, then promotes it into \`/data/managed-repository\`. One previous checkout is retained for **ROLLBACK**. Both the source settings and release files persist in \`./web/data\`. The mounted source \`ATTACC_REPOSITORY_PATH\` remains a fallback until the first successful sync.

On a new CC:Tweaked machine:

\`\`\`lua
wget https://your-domain/repo/install.lua install
install --source https://your-domain/repo
pkgctl source show
pkgctl source test
pkgctl status
\`\`\`

On an already installed AttaCC computer: first manually replace its old \`pkgctl.lua\` with the version from the new URL, **or run the newly downloaded installer**. Once updated:

\`\`\`lua
pkgctl source set https://your-domain/repo
pkgctl source test
pkgctl update
reboot
\`\`\`

To switch a migrated client back to the GitHub fallback: \`pkgctl source github\`.

Use **HTTPS** for the public URL and ensure CC:Tweaked HTTP allowlists permit your service's host. The backend git sync does not require network connectivity from the CC machines.

### Limitations / release precautions

- The generated \`install.lua\` is not self-locating when copied by \`wget\`; pass \`--source\` on the first installation.
- Git source registration and sync are administrator-only operations. Anonymous read-only \`/repo/\` paths are intended for CC clients.
- Synchronization can temporarily expose a small gap during directory promotion; avoid high-concurrency installs during sync.
- This uses shallow clone with \`--branch\`; tags and branch names work if advertised by the Git remote.
- An isolated snapshot is promoted as a whole, but there are not yet immutable, version-addressed package URLs for clients that update during a publication.
- Operational testing in CraftOS and final build of Web UI are required before merge.


## Autonomous Web repository (no personal GitHub repository required)

The **WebUI repository is the authoritative editable source** once initialized:

1. In **REPOSITORY**, save the public package URL (the URL reachable by CraftOS).
2. Click **INITIALIZE LOCAL REPO**. This copies the bundled AttaCC source into the persistent Docker volume at \`web/data/managed-repository\`. It does not clone or authenticate to GitHub.
3. The file browser allows opening and editing Lua, package manifests and documentation, creating new paths, and deleting optional files.
4. **Create app / module / preset** inserts a new definition into \`packages/manifest.lua\`. Create its referenced source file using the file editor before trying to install it. For more complex packages, edit the manifest to declare additional dependencies and source files.
5. Git options are under **Optional Git import / recovery**. They are unnecessary to install, update, or create AttaCC packages.

### Bootstrap from WebUI URL

The HTTP endpoint \`GET /repo/install.lua\` serves an installer that automatically picks up the WebUI's **Public package URL** unless a local source was already configured. This lets a **new CC** run:

\`\`\`lua
wget http://192.168.1.202:8080/repo/install.lua install
install
pkgctl source show
pkgctl source test
\`\`\`

It should persist \`/etc/pkgctl/source.lua\` pointing to \`http://192.168.1.202:8080/repo\`. Existing CCs still running the *old* \`pkgctl\` cannot understand \`source\`; migrate the program first:

\`\`\`lua
wget http://192.168.1.202:8080/repo/pkgctl.lua pkgctl-new.lua
mv pkgctl-new.lua pkgctl.lua
pkgctl source set http://192.168.1.202:8080/repo
pkgctl source show
pkgctl source test
pkgctl update
\`\`\`

**IMPORTANT:** the source is selected by the file \`/etc/pkgctl/source.lua\`; merely opening the URL in a browser or downloading \`install.lua\` does **not** change an already installed \`pkgctl\`. A local source is intentionally retained by the installer.

### Validating authored packages

Use the UI file editor to create, for example, \`apps/example/main.lua\`; create the corresponding package definition (kind=app, name=example, src=\`apps/example/main.lua\`, dest=\`example.lua\`). On a CC:

\`\`\`lua
pkgctl source test
pkgctl list
pkgctl install app.example
\`\`\`

The package wizard does not automatically create a runnable application entrypoint or install it as a boot preset. For boot presets, add the required application dependency and startup behavior separately; preset installation alone follows AttaCC's existing runtime conventions.

### Limitations

- Saving a Lua file does not currently run CraftOS/Lua syntax checks. Mistakes in package manifests may prevent package operations; keep backups.
- Git import **replaces** the current locally edited repository. It is not a two-way synchronization or merge.
- Manual edits become visible immediately, not through an immutable revision. Test updates on a spare CC first.
- Publish behind HTTPS with an admin token kept private. Repository package contents are public for clients.
- \`pkgctl source github\` remains an emergency fallback for clients; it is not used when a local source is set.
