# Maintenance

## Release process

1. Update a pinned image (see [UPSTREAM.md](UPSTREAM.md)) or the wrapper scripts.
2. Run the full local suite:
   ```bash
   tests/static.sh && docker compose build && tests/smoke.sh && tests/persistence.sh
   ```
3. Commit on `main`. CI (`test.yml`) runs the same suite on every push and pull request.
4. Tag and push:
   ```bash
   git tag -a vX.Y.Z -m "spoolman-railway vX.Y.Z" && git push origin vX.Y.Z
   ```
   `publish-image.yml` builds an amd64 candidate, runs the suite against **that** image, and only
   then pushes the multi-arch image to `ghcr.io/youssefsiam38/spoolman-railway:X.Y.Z`.
5. Note the digest from the workflow summary.
6. Point the template at the new tag:
   ```bash
   npx -y @railway/cli@latest templates update spoolman --readme-file marketplace/OVERVIEW.md
   ```
   or patch the service image through the template editor. Railway's template generator rejects
   `@sha256:` references, so templates use the version tag; the tag is immutable in practice because
   releases never re-push an existing tag. The marketplace overview lives in
   `marketplace/OVERVIEW.md`; Railway validates its section headings, so keep them.
7. Write release notes recording the wrapper version, both upstream versions and the image digest.

## What to watch

| Thing | Where | Why |
|---|---|---|
| Spoolman releases | https://github.com/Donkie/Spoolman/releases | schema migrations, new configuration, and above all whether it grows authentication of its own |
| Caddy releases | https://github.com/caddyserver/caddy/releases | the front door is the security boundary; keep it current |
| Railway template deploys | Railway dashboard | deploy failures show up as template health |

## Breaking-change checklist

Before releasing an upstream bump:

- [ ] Does the release change the health route? The readiness wait and the unauthenticated Caddy
      route both depend on `/api/v1/health`.
- [ ] Does it change the data directory or the uid it runs as? The entrypoint chowns the volume for
      uid 1000.
- [ ] Does it change the API paths the tests use (`vendor`, `filament`, `spool`, `spool/{id}/use`)?
- [ ] Does the version string change? Update the `info` assertions.
- [ ] Does Spoolman now have its own authentication? If so, reconsider the whole wrapper rather than
      stacking a second password on top.
- [ ] `tests/railway-smoke.sh` green against a staging deploy, including the persistence run with
      `STATE_OUT` / `STATE_IN` across a redeploy.

## Rolling back

Templates pin a version tag, so a bad release is undone by pointing the template back at the
previous tag and redeploying. Data lives in the volume and is untouched by an image rollback,
provided the newer version did not migrate the database forward.

## If this repository is abandoned

The template is a thin wrapper: fork it, change the GHCR path in the workflow and the template, and
publish your own. Nothing here depends on this account.
