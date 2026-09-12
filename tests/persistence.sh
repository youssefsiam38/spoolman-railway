#!/usr/bin/env bash
# shellcheck disable=SC2015
# Persistence: inventory and usage history survive recreating the container.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
umask 077
CREDS_FILE="$TEST_TMP/creds"; export CREDS_FILE
printf 'admin:%s' 'local-test-only-spoolman-password' > "$CREDS_FILE"

section "fresh stack"
compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d --no-build; wait_for_code "$BASE_URL/api/v1/health" 200 420 || die "not ready"

section "write state"
V=$(create_vendor "Persist Filaments"); [ -n "$V" ] || die "vendor create failed"
F=$(create_filament "$V" "Persist PLA" "PLA"); [ -n "$F" ] || die "filament create failed"
S=$(create_spool "$F"); [ -n "$S" ] || die "spool create failed"
use_filament "$S" 325 >/dev/null
assert_eq "spool partially used" "675" "$(jq -r '.remaining_weight | floor' <<<"$(spool_json "$S")")"
pass "state written: vendor $V, filament $F, spool $S"

section "recreate the container on the same volume"
compose down >/dev/null; compose up -d --no-build
wait_for_code "$BASE_URL/api/v1/health" 200 420 || die "not ready after recreate"

section "verify"
s=$(spool_json "$S")
assert_eq "spool still present" "675" "$(jq -r '.remaining_weight | floor' <<<"$s")"
assert_eq "used weight retained" "325" "$(jq -r '.used_weight | floor' <<<"$s")"
assert_eq "filament retained" "Persist PLA" "$(jq -r '.filament.name' <<<"$s")"
assert_eq "vendor retained" "Persist Filaments" "$(jq -r '.filament.vendor.name' <<<"$s")"
assert_eq "spool list retained" "1" "$(jq -r 'length' <<<"$(spools)")"
assert_eq "credentials unchanged" "200" "$(auth_code "$BASE_URL/api/v1/spool")"
assert_eq "anonymous still refused" "401" "$(http_code "$BASE_URL/api/v1/spool")"
use_filament "$S" 75 >/dev/null
assert_eq "still writable after recreate" "600" "$(jq -r '.remaining_weight | floor' <<<"$(spool_json "$S")")"
summary
