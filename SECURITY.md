# Security

## Reporting

Problems in **this wrapper** (entrypoint, front door, template configuration): open an issue at
https://github.com/youssefsiam38/spoolman-railway/issues. If the problem is exploitable, use
GitHub's private vulnerability reporting on that repository instead of a public issue.

Problems in **Spoolman itself**: report upstream at https://github.com/Donkie/Spoolman/issues.

## The central fact

Spoolman ships with no authentication, by design. Upstream states it plainly in
`spoolman/security.py`: the network is the boundary that protects the data. On a home LAN that is a
reasonable trade. On Railway, where every service gets a public HTTPS domain, there is no such
boundary, and the stock image on a public URL is a writable database open to the internet.

This template adds the boundary back: Caddy holds the public port and requires a password, and
Spoolman is bound to loopback inside the container where nothing external can reach it. The wrapper
refuses to start if you try to move Spoolman off loopback or to run without a password.

## What is exposed

| Surface | Anonymous access |
|---|---|
| web interface, the whole `/api/v1` surface, backups | refused, HTTP 401 |
| `/api/v1/health` | open; returns `{"status":"healthy"}` and nothing else |
| Spoolman's own listener on port 8765 | loopback only, never published |

## Deliberately opting out

`SPOOLMAN_ALLOW_PUBLIC=true` removes the password. The wrapper honours it, logs a warning on every
boot, and the smoke test checks that both things happen. Only use it if an open, world-writable
inventory is genuinely what you want.

## Secrets

- `SPOOLMAN_AUTH_PASSWORD` is generated per deployment by the template.
- The wrapper prints variable **names**, lengths and outcomes — never values. The test suite asserts
  that neither the password nor its bcrypt hash appears in the container log.
- The password is hashed before it is written anywhere; the Caddy configuration holds only the hash
  and is mode 600, owned by the app user.
- Changing the password means editing the Railway variable and redeploying. There is no in-app
  password to drift out of sync with it.
- The value in `compose.yaml` is labelled local-test-only and exists so the suite can assert it
  never appears in logs. It is not a secret and must not be reused.

## Client credentials

Printer integrations authenticate by putting the credentials in the URL,
`https://user:password@host`. That means the password appears in the printer's configuration file
and in its logs. Treat the deployment's password as shared with every machine you connect, and
rotate it in the Railway dashboard if one of them is compromised.

## Transport

Railway terminates TLS at the edge and forwards to Caddy over the internal network. Caddy runs with
`auto_https off` because it never faces the internet directly, and proxies to Spoolman over
loopback. Basic authentication is only as safe as the transport, which is why the template's public
URL is HTTPS and the documentation never suggests plain HTTP.

## Third-party calls made by the application

Spoolman fetches the public filament database from `donkie.github.io` at start-up to populate the
material and vendor pickers. No inventory data leaves the deployment.

## Updates

Both base images are pinned by tag **and** digest; the workflow publishes multi-arch images and the
release notes record the digest. See [MAINTENANCE.md](MAINTENANCE.md).
