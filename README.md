# Spoolman on Railway

Know how much filament is left on every spool. **Spoolman** is a 3D-printing filament inventory:
record your spools, vendors and materials, and let your printer subtract what it uses as it prints.
Klipper, Moonraker, OctoPrint, Home Assistant and the Bambu and Prusa ecosystems all talk to it.
This repository is a **community-maintained Railway template** for
[Spoolman](https://github.com/Donkie/Spoolman). It is **not affiliated with the Spoolman project**.

<!-- DEPLOY_BUTTON_START -->
[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/spoolman)

Template page: https://railway.com/deploy/spoolman
<!-- DEPLOY_BUTTON_END -->

> **Read this before deploying.** Spoolman has no authentication of its own. Upstream is explicit
> about it: *"Spoolman has no authentication by design; the boundary that protects a user's data is
> the network."* Railway gives every service a public URL, which removes that boundary, so this
> template puts a password in front of it. See [SECURITY.md](SECURITY.md).

> **Licence.** Spoolman is **MIT** and so is the wrapper in this repository. The image also carries
> Caddy, which is Apache-2.0. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## What you get

| Service | Source | Public | Volume |
|---|---|---|---|
| `spoolman` | `ghcr.io/youssefsiam38/spoolman-railway:<version>` wrapping `ghcr.io/donkie/spoolman:0.26.1` | yes, with a password | `/home/app/.local/share/spoolman` — SQLite database, backups, logs |

| Component | Version |
|---|---|
| Spoolman | 0.26.1 |
| Caddy (the authenticating front door) | 2.10.2 |
| Wrapper | v1.0.0 — `ghcr.io/youssefsiam38/spoolman-railway:1.0.0` ([releases](https://github.com/youssefsiam38/spoolman-railway/releases)) |

One service, one volume, no external database. Why a wrapper:
[ARCHITECTURE.md](ARCHITECTURE.md). In one sentence: Caddy holds the public port and asks for a
password, Spoolman listens only on loopback, and nothing reaches the inventory without credentials.

## First run

1. Click **Deploy on Railway**. Nothing has to be filled in: the password is generated.
2. Read `SPOOLMAN_AUTH_PASSWORD` in the Railway dashboard under the `spoolman` service's Variables
   tab, clicking it to reveal.
3. Open the service's public URL. The browser asks for a username and password. The username is
   `admin` unless you changed `SPOOLMAN_AUTH_USERNAME`.
4. Add a vendor, a filament and a spool, or use **Add spools** and pick from the built-in filament
   database.
5. Point your printer at it. In Moonraker, set the Spoolman server URL with the credentials
   embedded:
   ```ini
   [spoolman]
   server: https://admin:YOUR_PASSWORD@your-app.up.railway.app
   ```
   The same form works for OctoPrint's Spoolman plugin and for Home Assistant.

To change the password later, edit `SPOOLMAN_AUTH_PASSWORD` in the Railway dashboard. Unlike an
in-app password, this one is the deployment's own, so the variable stays authoritative.

## Environment variables

| Variable | Required | Set by template | Description |
|---|---|---|---|
| `SPOOLMAN_AUTH_PASSWORD` | yes | generated `${{secret(24)}}` | Password for the front door. At least 12 characters. |
| `SPOOLMAN_AUTH_USERNAME` | no | `admin` | Username for the front door. |
| `SPOOLMAN_ALLOW_PUBLIC` | no | unset | Set `true` to remove the password entirely. Anyone who finds the URL can then read and edit your inventory. |
| `PORT` | no | `8000` | Port the front door listens on. Railway probes its healthcheck here, so keep it equal to the domain's target port. |
| `SPOOLMAN_INTERNAL_PORT` | no | `8765` | Loopback port Spoolman itself listens on. Never exposed. |
| `SPOOLMAN_DIR_DATA` | no | image default | Where the database lives. Must match the volume mount. |
| `TZ` | no | `UTC` | Timezone used for timestamps. |
| `SPOOLMAN_AUTOMATIC_BACKUP` | no | unset (upstream default: on) | Nightly backup into the volume. |
| `SPOOLMAN_CORS_ORIGIN` | no | unset | Extra browser origins allowed to call the API. |
| `SPOOLMAN_DB_TYPE` and friends | no | unset | Use an external Postgres, MySQL or CockroachDB instead of SQLite. |
| `SPOOLMAN_HOST` | no | **refused** | The wrapper pins Spoolman to loopback and refuses to start if you try to move it. |

Everything in Spoolman's own configuration works as usual; see
[its documentation](https://github.com/Donkie/Spoolman#configuration).

## Persistent paths

| Path | Contents | Backup |
|---|---|---|
| `/home/app/.local/share/spoolman` | `spoolman.db`, `backups/`, `cache/`, logs | `railway volume files download` |

## Local development

```bash
docker compose build
docker compose up -d
```

Then open http://127.0.0.1:8000 and sign in as `admin`. The compose file uses an obvious
local-test-only password; do not reuse it.

Tests:

```bash
tests/static.sh       # syntax, shellcheck, pinning, the front door cannot be configured away
tests/smoke.sh        # cold start, anonymous refusal, inventory workflow, fail-fast checks
tests/persistence.sh  # inventory survives recreating the container
tests/railway-smoke.sh https://your-app.up.railway.app   # against a deployment
```

## Documentation

| File | Contents |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | the front door, why it exists, boot sequence |
| [RAILWAY_TEMPLATE.md](RAILWAY_TEMPLATE.md) | exact template configuration |
| [SECURITY.md](SECURITY.md) | threat model, what is exposed, reporting |
| [UPSTREAM.md](UPSTREAM.md) | upstream provenance and how to bump it |
| [MAINTENANCE.md](MAINTENANCE.md) | release process and update checklist |
| [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) | licences of everything shipped |
| [MARKETPLACE_AUDIT.md](MARKETPLACE_AUDIT.md) | why this template was built |

## Licence

Wrapper code in this repository: MIT ([LICENSE](LICENSE)). Spoolman is MIT and Caddy is Apache-2.0;
see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
