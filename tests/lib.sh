#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass || fail` is intentional; pass/fail always succeed
# Shared helpers for spoolman-railway tests. Source this file; do not execute it.
# Secrets are never echoed. Only names, lengths, and pass/fail results are printed.

: "${BASE_URL:=http://127.0.0.1:8000}"
: "${TEST_TIMEOUT:=300}"

TEST_TMP="${TEST_TMP:-$(mktemp -d)}"
export TEST_TMP
_PASS=0; _FAIL=0

pass() { _PASS=$((_PASS+1)); printf '  PASS  %s\n' "$*"; }
fail() { _FAIL=$((_FAIL+1)); printf '  FAIL  %s\n' "$*" >&2; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
section() { printf '\n== %s ==\n' "$*"; }
summary() { printf '\n%d passed, %d failed\n' "$_PASS" "$_FAIL"; [ "$_FAIL" -eq 0 ]; }

# here-strings, not pipes: `grep -q` exits on the first match and a pipe writer would get SIGPIPE,
# which `pipefail` reports as failure when the haystack is larger than the pipe buffer
assert_eq() { if [ "$2" = "$3" ]; then pass "$1 ($3)"; else fail "$1: expected [$2] got [$3]"; fi; }
assert_contains() { if grep -q -- "$2" <<<"$3"; then pass "$1"; else fail "$1: missing [$2]"; fi; }
assert_not_contains() { if grep -q -- "$2" <<<"$3"; then fail "$1: found forbidden [$2]"; else pass "$1"; fi; }

# CREDS_FILE holds "username:password" and is never printed.
creds() { cat "${CREDS_FILE:?CREDS_FILE not set}"; }

http_code()  { curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$@"; }
auth_code()  { curl -s -o /dev/null -w '%{http_code}' --max-time 30 -u "$(creds)" "$@"; }

wait_for_code() {
  local url=$1 want=$2 timeout=${3:-$TEST_TIMEOUT} start code
  start=$(date +%s)
  while :; do
    code=$(http_code "$url" || true)
    [ "$code" = "$want" ] && return 0
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then printf 'timed out waiting for %s -> %s (last %s)\n' "$url" "$want" "$code" >&2; return 1; fi
    sleep 3
  done
}

# req_json TIMEOUT curl-args... -> body, retried while the response is not JSON. Always authenticated.
req_json() {
  local timeout=$1; shift
  local start body code
  start=$(date +%s)
  while :; do
    body=$(curl -s -w '\n%{http_code}' --max-time 60 -u "$(creds)" "$@" || true)
    code=${body##*$'\n'}; body=${body%$'\n'*}
    if jq -e . >/dev/null 2>&1 <<<"$body"; then printf '%s' "$body"; return 0; fi
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then
      printf 'non-JSON response after %ss (HTTP %s) from: %s\n  body: %s\n' "$timeout" "$code" "$*" "$(head -c 200 <<<"$body")" >&2
      return 1
    fi
    sleep 3
  done
}

api()     { req_json 120 "$BASE_URL$1"; }
info()    { api /api/v1/info; }
vendors() { api /api/v1/vendor; }
spools()  { api /api/v1/spool; }

# create_vendor NAME -> prints the vendor id
create_vendor() {
  req_json 120 -X POST "$BASE_URL/api/v1/vendor" -H 'Content-Type: application/json' \
    --data "$(jq -nc --arg n "$1" '{name:$n}')" | jq -r '.id // empty'
}
# create_filament VENDOR_ID NAME MATERIAL -> prints the filament id
create_filament() {
  req_json 120 -X POST "$BASE_URL/api/v1/filament" -H 'Content-Type: application/json' \
    --data "$(jq -nc --argjson v "$1" --arg n "$2" --arg m "$3" \
      '{name:$n, vendor_id:$v, material:$m, density:1.24, diameter:1.75, weight:1000}')" | jq -r '.id // empty'
}
# create_spool FILAMENT_ID -> prints the spool id
create_spool() {
  req_json 120 -X POST "$BASE_URL/api/v1/spool" -H 'Content-Type: application/json' \
    --data "$(jq -nc --argjson f "$1" '{filament_id:$f, initial_weight:1000, spool_weight:200}')" | jq -r '.id // empty'
}
spool_json() { api "/api/v1/spool/$1"; }
# use_filament SPOOL_ID GRAMS
use_filament() {
  req_json 120 -X PUT "$BASE_URL/api/v1/spool/$1/use" -H 'Content-Type: application/json' \
    --data "$(jq -nc --argjson g "$2" '{use_weight:$g}')"
}
compose() { docker compose -f "$REPO_ROOT/compose.yaml" "$@"; }
