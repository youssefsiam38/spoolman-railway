# Upstream provenance

## Spoolman

| | |
|---|---|
| Project | [Spoolman](https://github.com/Donkie/Spoolman) |
| Version deployed | 0.26.1 |
| Licence | MIT |
| Image | `ghcr.io/donkie/spoolman:0.26.1` |
| Digest | `sha256:cf9b41e17b93ce7d4ca584d9809142f8918fd290f2cd7d3b8b12ff76c75482f0` |
| Source for the tag | https://github.com/Donkie/Spoolman/tree/v0.26.1 |
| Platforms | linux/amd64, linux/arm64, linux/arm/v7 |

## Caddy

| | |
|---|---|
| Project | [Caddy](https://github.com/caddyserver/caddy) |
| Version | 2.10.2 |
| Licence | Apache-2.0 |
| Image | `docker.io/library/caddy:2.10-alpine` |
| Digest | `sha256:4c6e91c6ed0e2fa03efd5b44747b625fec79bc9cd06ac5235a779726618e530d` |

Only the `caddy` binary is copied out of that image, in a build stage. It is a static Go binary, so
it runs unchanged on Spoolman's Debian base.

## What this repository changes

Nothing in the application. The wrapper image is `FROM ghcr.io/donkie/spoolman` plus:

| Added | Path | Why |
|---|---|---|
| Caddy binary | `/usr/local/bin/caddy` | the authenticating front door Spoolman does not have |
| entrypoint | `/usr/local/bin/spoolman-railway-entrypoint` | validation, data-directory ownership, config generation, readiness wait, supervision |
| licences | `/usr/share/licenses/spoolman-railway/` | MIT and Apache-2.0 texts shipped with the binary |
| `SPOOLMAN_HOST=127.0.0.1`, `SPOOLMAN_INTERNAL_PORT=8765` | env | keeps the app off the public interface |
| OCI labels | image metadata | source, revision, version, upstream version, Caddy version |

No patches, no forks, no rebuilt assets.

## Licence obligations

Spoolman is MIT and Caddy is Apache-2.0. Both are permissive: redistributing the image requires
preserving their licence texts and notices, which the image does at
`/usr/share/licenses/spoolman-railway/`. The wrapper's own code is MIT.

## Bumping the upstream version

1. Find the new release at https://github.com/Donkie/Spoolman/releases and read it for schema or
   configuration changes.
2. Resolve the new digest:
   ```bash
   docker buildx imagetools inspect ghcr.io/donkie/spoolman:X.Y.Z --format '{{.Manifest.Digest}}'
   ```
3. Update `SPOOLMAN_IMAGE` and `SPOOLMAN_VERSION` in `Dockerfile`, plus the version tables in
   `README.md`, this file, and the version assertions in `tests/smoke.sh` and
   `tests/railway-smoke.sh`.
4. `tests/static.sh && docker compose build && tests/smoke.sh && tests/persistence.sh`.
5. Follow [MAINTENANCE.md](MAINTENANCE.md) to release and to update the template image.

Check in particular whether the release adds authentication of its own. If upstream ever grows a
login, this wrapper's front door becomes redundant and the template should be reconsidered rather
than stacked on top of it.
