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
