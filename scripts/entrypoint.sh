#!/bin/bash
# spoolman-railway entrypoint.
#
#   1. validate variables (names only; values are never printed)
#   2. put Spoolman on loopback and Caddy, with HTTP basic authentication, on the public port
#   3. supervise both; if either exits, the container exits
#
# Spoolman has no authentication of its own. Upstream is explicit that the network is the boundary
# protecting the data, and a public URL removes that boundary, so the wrapper restores it.
set -uo pipefail

log()  { printf '[spoolman-railway] %s\n' "$*" >&2; }
fail() { log "FATAL: $*"; exit 1; }

: "${SPOOLMAN_HOST:=127.0.0.1}"
: "${SPOOLMAN_INTERNAL_PORT:=8765}"
: "${SPOOLMAN_AUTH_USERNAME:=admin}"
: "${SPOOLMAN_DIR_DATA:=/home/app/.local/share/spoolman}"
CADDYFILE=/etc/spoolman-railway/Caddyfile

# The public listener takes the platform's PORT. Railway probes its healthcheck against that value
# (8080 when unset), so an app that ignores PORT is reported unhealthy however well it serves.
PUBLIC_PORT="${PORT:-8000}"
case "$PUBLIC_PORT" in
  ''|*[!0-9]*) fail "PORT must be a number, got \"$PUBLIC_PORT\"" ;;
esac
if [ "$PUBLIC_PORT" = "$SPOOLMAN_INTERNAL_PORT" ]; then
  fail "PORT and SPOOLMAN_INTERNAL_PORT are both $PUBLIC_PORT. The public listener and the app cannot share a port; change SPOOLMAN_INTERNAL_PORT."
fi

case "$SPOOLMAN_HOST" in
  127.0.0.1|localhost|::1) ;;
  *) fail "SPOOLMAN_HOST is \"$SPOOLMAN_HOST\". This image binds Spoolman to loopback on purpose: it has no authentication, and exposing it directly would publish a writable database. Remove the variable." ;;
esac

ALLOW_PUBLIC="${SPOOLMAN_ALLOW_PUBLIC:-false}"
if [ "$ALLOW_PUBLIC" != "true" ]; then
  [ -n "${SPOOLMAN_AUTH_PASSWORD:-}" ] || fail "missing required variable: SPOOLMAN_AUTH_PASSWORD. Spoolman has no authentication of its own, so without this anyone who finds the URL can read and edit your inventory. Set a password, or set SPOOLMAN_ALLOW_PUBLIC=true if you really want an open instance."
  [ "${#SPOOLMAN_AUTH_PASSWORD}" -ge 12 ] || fail "SPOOLMAN_AUTH_PASSWORD must be at least 12 characters"
  [ -n "$SPOOLMAN_AUTH_USERNAME" ] || fail "SPOOLMAN_AUTH_USERNAME must not be empty"
fi

# Railway mounts volumes owned by root; Spoolman runs as uid 1000 and never chowns its own data
# directory, so a fresh volume would be read-only to it.
mkdir -p "$SPOOLMAN_DIR_DATA" || fail "cannot create $SPOOLMAN_DIR_DATA"
chown -R app:app "$SPOOLMAN_DIR_DATA" 2>/dev/null || log "WARNING: could not chown $SPOOLMAN_DIR_DATA; continuing"

if [ "$ALLOW_PUBLIC" = "true" ]; then
  log "WARNING: SPOOLMAN_ALLOW_PUBLIC=true. Authentication is disabled and anyone who reaches this URL can read and edit the inventory."
  cat > "$CADDYFILE" <<EOF
{
	admin off
	auto_https off
	persist_config off
}
:${PUBLIC_PORT} {
	reverse_proxy 127.0.0.1:${SPOOLMAN_INTERNAL_PORT}
}
EOF
else
  hash=$(caddy hash-password --plaintext "$SPOOLMAN_AUTH_PASSWORD" 2>/dev/null) \
    || fail "could not hash SPOOLMAN_AUTH_PASSWORD"
  [ -n "$hash" ] || fail "empty password hash"
  cat > "$CADDYFILE" <<EOF
{
	admin off
	auto_https off
	persist_config off
}
:${PUBLIC_PORT} {
	# The platform healthcheck has no credentials to offer. This route reports only
	# {"status":"healthy"} and holds no inventory data.
	handle /api/v1/health {
		reverse_proxy 127.0.0.1:${SPOOLMAN_INTERNAL_PORT}
	}
	handle {
		basic_auth {
			${SPOOLMAN_AUTH_USERNAME} ${hash}
		}
		reverse_proxy 127.0.0.1:${SPOOLMAN_INTERNAL_PORT}
	}
}
EOF
  unset hash
  log "authentication enabled for user \"${SPOOLMAN_AUTH_USERNAME}\" (password length ${#SPOOLMAN_AUTH_PASSWORD})"
fi
chown app:app "$CADDYFILE" && chmod 600 "$CADDYFILE"
caddy validate --config "$CADDYFILE" --adapter caddyfile >/dev/null 2>&1 \
  || fail "generated Caddy configuration is invalid"

export SPOOLMAN_HOST SPOOLMAN_PORT="$SPOOLMAN_INTERNAL_PORT"

log "starting Spoolman on ${SPOOLMAN_HOST}:${SPOOLMAN_INTERNAL_PORT} behind the public listener on :${PUBLIC_PORT}"
/home/app/spoolman/entrypoint.sh &
spoolman_pid=$!

# Wait for the app before accepting public traffic, so nobody sees a proxy error on a cold start.
# The image ships no curl or wget, but Spoolman's own interpreter is always present.
: "${APP_READY_TIMEOUT:=180}"
ready() {
  python3 - "$1" <<'PYEOF' 2>/dev/null
import sys, urllib.request
try:
    with urllib.request.urlopen(sys.argv[1], timeout=5) as r:
        sys.exit(0 if r.status == 200 else 1)
except Exception:
    sys.exit(1)
PYEOF
}
deadline=$(( $(date +%s) + APP_READY_TIMEOUT ))
until ready "http://127.0.0.1:${SPOOLMAN_INTERNAL_PORT}/api/v1/health"; do
  kill -0 "$spoolman_pid" 2>/dev/null || fail "Spoolman exited during start-up"
  [ "$(date +%s)" -lt "$deadline" ] || fail "Spoolman did not become healthy within ${APP_READY_TIMEOUT}s"
  sleep 2
done
log "Spoolman is healthy; opening the public listener"

gosu app caddy run --config "$CADDYFILE" --adapter caddyfile &
caddy_pid=$!

trap 'kill -TERM "$spoolman_pid" "$caddy_pid" 2>/dev/null' TERM INT
wait -n "$spoolman_pid" "$caddy_pid"
status=$?
log "a supervised process exited with status ${status}; shutting down"
kill -TERM "$spoolman_pid" "$caddy_pid" 2>/dev/null
wait 2>/dev/null
exit "$status"
