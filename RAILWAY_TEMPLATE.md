# Railway template configuration

The published template. Reproduce it from this file if it ever has to be rebuilt.

| | |
|---|---|
| Name | Spoolman |
| Code | `spoolman` |
| Category | Other |
| Image | `ghcr.io/youssefsiam38/spoolman-railway:<version>` |
| Icon | `assets/icon.png` |
| Overview markdown | `marketplace/OVERVIEW.md` (Railway enforces its section headings) |

## Service `spoolman` — public

| Field | Value |
|---|---|
| Source | `ghcr.io/youssefsiam38/spoolman-railway:<version>` |
| Port | 8000 |
| Domain | generated, target port 8000 |
| Healthcheck | `/api/v1/health` |
| Volume | `/home/app/.local/share/spoolman` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `SPOOLMAN_AUTH_USERNAME` | `admin` |
| `SPOOLMAN_AUTH_PASSWORD` | `${{secret(24)}}` |
| `PORT` | `8000` |
| `TZ` | `UTC` |

## Notes

- Every variable has a value or a generator, so `railway deploy -t spoolman` works without a TTY.
- **The healthcheck path must be `/api/v1/health`, not `/`.** Everything else is behind basic
  authentication and answers 401, which Railway treats as unhealthy. That one route is deliberately
  left open and returns only `{"status":"healthy"}`.
- **`PORT` and the domain's target port must match.** Railway runs its healthcheck against the
  value of `PORT`, defaulting to 8080. A service that serves the public domain perfectly still
  fails to deploy if nothing listens on `PORT`.
- Do not add `SPOOLMAN_HOST`. The image pins Spoolman to loopback and the wrapper refuses to start
  if that is overridden, because moving it would publish an unauthenticated, writable database.
- The volume mount path must match `SPOOLMAN_DIR_DATA`, which is left at the image default.
- There is no second service and nothing on the private network.
