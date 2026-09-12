#!/usr/bin/env bash
# shellcheck disable=SC2015
# Public smoke test against a deployed instance.
#   tests/railway-smoke.sh https://your-app.up.railway.app
# Optional: CREDS_FILE=/path/to/file holding "username:password"
#   STATE_OUT=/path/state.json (create a spool) / STATE_IN=/path/state.json (verify after redeploy)
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
BASE_URL=${1:?usage: railway-smoke.sh https://domain}; BASE_URL=${BASE_URL%/}; export BASE_URL
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
host=${BASE_URL#https://}

section "TLS and routing"
assert_eq "health route answers over https" "200" "$(http_code "$BASE_URL/api/v1/health")"
assert_contains "valid certificate" "SSL certificate verify ok" "$(curl -sv -o /dev/null "$BASE_URL/api/v1/health" 2>&1 || true)"
assert_contains "http -> https" "https://$host" "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 20 "http://$host/api/v1/health")"

section "the instance is not open to the internet"
assert_eq "web interface refused" "401" "$(http_code "$BASE_URL/")"
assert_eq "spool list refused" "401" "$(http_code "$BASE_URL/api/v1/spool")"
assert_eq "vendor list refused" "401" "$(http_code "$BASE_URL/api/v1/vendor")"
assert_eq "instance info refused" "401" "$(http_code "$BASE_URL/api/v1/info")"
assert_eq "writes refused" "401" "$(http_code -X POST "$BASE_URL/api/v1/vendor" -H 'Content-Type: application/json' --data '{"name":"Intruder"}')"
assert_eq "backup endpoint refused" "401" "$(http_code -X POST "$BASE_URL/api/v1/backup")"
assert_eq "wrong password refused" "401" "$(http_code -u "admin:wrong-password-entirely" "$BASE_URL/api/v1/spool")"
assert_eq "health route leaks nothing but a status" '{"status":"healthy"}' "$(curl -s --max-time 20 "$BASE_URL/api/v1/health")"

if [ -n "${CREDS_FILE:-}" ]; then
  section "signed in through the public domain"
  assert_eq "web interface served" "200" "$(auth_code "$BASE_URL/")"
  i=$(info)
  assert_eq "version reported" "0.26.1" "$(jq -r .version <<<"$i")"
  assert_eq "sqlite backend" "sqlite" "$(jq -r .db_type <<<"$i")"

  if [ -n "${STATE_OUT:-}" ]; then
    section "create inventory"
    V=$(create_vendor "Railway Filaments"); [ -n "$V" ] && pass "vendor created (id $V)" || die "vendor create failed"
    F=$(create_filament "$V" "Railway PLA" "PLA"); [ -n "$F" ] && pass "filament created (id $F)" || die "filament create failed"
    S=$(create_spool "$F"); [ -n "$S" ] && pass "spool created (id $S)" || die "spool create failed"
    use_filament "$S" 325 >/dev/null
    assert_eq "usage subtracted" "675" "$(jq -r '.remaining_weight | floor' <<<"$(spool_json "$S")")"
    jq -n --argjson s "$S" --arg n "Railway PLA" '{spool:$s, filament_name:$n, remaining:675}' > "$STATE_OUT"
    pass "state written"
  fi

  if [ -n "${STATE_IN:-}" ]; then
    section "verify state after redeploy"
    S=$(jq -r .spool "$STATE_IN")
    s=$(spool_json "$S")
    assert_eq "spool still present" "$(jq -r .remaining "$STATE_IN")" "$(jq -r '.remaining_weight | floor' <<<"$s")"
    assert_eq "filament retained" "$(jq -r .filament_name "$STATE_IN")" "$(jq -r '.filament.name' <<<"$s")"
    assert_eq "still writable" "200" "$(auth_code -X PUT "$BASE_URL/api/v1/spool/$S/use" -H 'Content-Type: application/json' --data '{"use_weight":25}')"
  fi
fi
summary
