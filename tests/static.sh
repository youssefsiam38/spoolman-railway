#!/usr/bin/env bash
# shellcheck disable=SC2015
# Static validation: shell syntax, shellcheck, compose config, Dockerfile pins.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
cd "$REPO_ROOT"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

section "shell syntax"
for f in scripts/*.sh tests/*.sh; do
  if bash -n "$f" 2>/dev/null; then pass "parses: $f"; else fail "syntax error: $f"; fi
done

section "shellcheck"
if command -v shellcheck >/dev/null; then
  if shellcheck -s bash scripts/*.sh; then pass "shellcheck scripts"; else fail "shellcheck scripts"; fi
  if shellcheck -x -s bash tests/*.sh; then pass "shellcheck tests"; else fail "shellcheck tests"; fi
else
  echo "  SKIP  shellcheck not installed"
fi

section "compose"
if docker compose -f compose.yaml config >/dev/null; then pass "compose config"; else fail "compose config"; fi

section "dockerfile pins"
df=$(cat Dockerfile)
assert_contains "Spoolman pinned by tag and digest" 'ghcr.io/donkie/spoolman:0.26.1@sha256:' "$df"
assert_contains "Caddy pinned by tag and digest" 'caddy:2.10-alpine@sha256:' "$df"
assert_contains "entrypoint is the wrapper" 'ENTRYPOINT \["/usr/local/bin/spoolman-railway-entrypoint"\]' "$df"
assert_contains "Spoolman bound to loopback in the image" 'SPOOLMAN_HOST=127.0.0.1' "$df"
if grep -qE '^\s+SPOOLMAN_PORT=' Dockerfile; then fail "SPOOLMAN_PORT must not be baked in; it would shadow the platform's PORT"; else pass "public port left to the entrypoint"; fi

section "the front door cannot be configured away"
ep=$(cat scripts/entrypoint.sh)
assert_contains "refuses a non-loopback SPOOLMAN_HOST" 'binds Spoolman to loopback on purpose' "$ep"
assert_contains "requires a password unless explicitly opted out" 'missing required variable: SPOOLMAN_AUTH_PASSWORD' "$ep"
assert_contains "only the health route skips authentication" 'handle /api/v1/health' "$ep"
assert_contains "everything else is behind basic auth" 'basic_auth' "$ep"
assert_contains "the generated config is validated before use" 'caddy validate' "$ep"

section "workflows"
for wf in .github/workflows/*.yml; do
  if grep -qE 'uses: .*@[0-9a-f]{40}' "$wf" && ! grep -qE 'uses: .*@v[0-9]+\s*$' "$wf"; then
    pass "actions pinned by SHA in $wf"
  else
    fail "unpinned action in $wf"
  fi
done

section "no tracked secrets"
if git rev-parse --git-dir >/dev/null 2>&1; then
  if git grep -nIE '(BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|xox[baprs]-)' -- . >/dev/null 2>&1; then
    fail "credential pattern in tracked files"
  else
    pass "no credential patterns in tracked files"
  fi
  if git ls-files --error-unmatch .env >/dev/null 2>&1; then fail ".env is tracked"; else pass ".env not tracked"; fi
else
  echo "  SKIP  not a git checkout"
fi
summary
