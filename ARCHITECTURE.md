# Architecture

## Service graph

```
                internet
                   │  https
                   ▼
   ┌───────────────────────────────────┐
   │  spoolman  (public)               │
   │                                   │
   │   Caddy  :$PORT                   │  basic auth, except /api/v1/health
   │     │  reverse proxy              │
   │     ▼                             │
   │   Spoolman  127.0.0.1:8765        │  uvicorn, no auth of its own
   │   volume /home/app/.local/...     │  SQLite + backups
   └───────────────────────────────────┘
```

One service, one volume. Spoolman keeps everything in a single data directory, which suits
Railway's one-volume-per-service model.

## Why a wrapper image

Spoolman has no authentication, and that is deliberate. From `spoolman/security.py` upstream:

> Spoolman has no authentication by design; the boundary that protects a user's data is the
> network.

That assumption holds on a home LAN. It does not hold on Railway, where every service is handed a
public HTTPS domain the moment it starts. Deployed raw, the result is a writable database on the
open internet: anyone who finds the URL can list your spools, edit them, trigger a backup, or wipe
them. This is not theoretical — an unauthenticated `POST /api/v1/vendor` against the stock image
creates a record, which is what the smoke test asserts the wrapper now prevents.

So the wrapper supplies the missing boundary:

1. Validate variables. Names, lengths and outcomes are printed; values never are.
2. Refuse configurations that would take the door off its hinges:
   - a `SPOOLMAN_HOST` that is not loopback, which would expose the app directly;
   - a missing or short `SPOOLMAN_AUTH_PASSWORD`, unless `SPOOLMAN_ALLOW_PUBLIC=true` says the
     operator means it;
   - a `PORT` that collides with the app's internal port.
3. Take ownership of the data directory, because Railway mounts volumes as root and Spoolman runs
   as uid 1000 without chowning anything itself.
4. Generate a Caddy configuration with a bcrypt hash of the password, and validate it before use.
5. Start Spoolman on loopback, **wait for it to report healthy**, and only then open the public
   listener, so nobody meets a proxy error during a cold start.
6. Supervise both processes. If either exits, the container exits and Railway restarts it.

Application code is untouched. The image adds Caddy, an entrypoint, the licence files and OCI
labels on top of the upstream image.

## The front door

Caddy holds the public port and proxies to `127.0.0.1:8765`. Every route requires HTTP basic
authentication except one:

| Route | Authentication | Why |
|---|---|---|
| `/api/v1/health` | none | Railway's healthcheck has no credentials to offer. The route returns `{"status":"healthy"}` and nothing else. |
| everything else | basic auth | the web interface, the whole API, backups |

The password is hashed with `caddy hash-password` at start-up; the plaintext never reaches the
config file on disk, and the config file is mode 600 and owned by the app user. The generated
configuration is checked with `caddy validate` before either process starts, so a malformed value
fails loudly instead of silently serving without a password.

Basic authentication was chosen because every Spoolman client speaks it through a URL:
`https://user:password@host`. Moonraker, the OctoPrint plugin and Home Assistant all accept that
form, so the template does not break the integrations that make Spoolman useful.

## Boot sequence

```
entrypoint ─► validate variables
              chown the data directory to uid 1000
              hash the password, write and validate the Caddyfile
           ─► start Spoolman on 127.0.0.1:8765
              poll /api/v1/health until it answers
           ─► start Caddy on :$PORT
              wait -n; either exit brings the container down
```

A cold start on an empty volume takes a few seconds; Spoolman then fetches the public filament
database in the background.

## Ports

| Port | Bound to | Purpose |
|---|---|---|
| `$PORT` (8000 by default) | all interfaces | Caddy, the only thing the outside world talks to |
| `8765` | 127.0.0.1 | Spoolman itself, unreachable from outside the container |

`PORT` matters for a second reason: Railway probes its healthcheck against the value of `PORT`,
defaulting to 8080, while public traffic goes to the domain's target port. A service can serve its
public URL perfectly and still fail every deploy if the two disagree, so the template sets `PORT`
and the domain target to the same value.

## Health and readiness

The healthcheck is `GET /api/v1/health` through the public port. It passes only after Caddy is
listening, and Caddy starts only after Spoolman answers its own health route, so a passing
healthcheck implies a usable, protected instance.
