#!/usr/bin/env bash
# shellcheck disable=SC2015
# Local smoke test. Run `docker compose build` first (CI does), or set SPOOLMAN_RAILWAY_IMAGE.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
mkdir -p "$REPO_ROOT/test-output"; METRICS="$REPO_ROOT/test-output/metrics.txt"
LOCAL_PASSWORD='local-test-only-spoolman-password'
umask 077
CREDS_FILE="$TEST_TMP/creds"; export CREDS_FILE
printf 'admin:%s' "$LOCAL_PASSWORD" > "$CREDS_FILE"

section "fresh stack (empty volume)"
compose down -v --remove-orphans >/dev/null 2>&1 || true
t0=$(date +%s); compose up -d --no-build
wait_for_code "$BASE_URL/api/v1/health" 200 420 && pass "health route answers" || { compose logs --no-color spoolman | tail -40; die "never became ready"; }
cold=$(( $(date +%s) - t0 )); echo "cold_start_seconds=$cold" | tee "$METRICS"

section "start-up"
logs=$(compose logs --no-color spoolman)
assert_contains "authentication was enabled" "authentication enabled for user" "$logs"
assert_contains "app waited for before the door opened" "Spoolman is healthy; opening the public listener" "$logs"
assert_contains "app bound to loopback" "Uvicorn running on http://127.0.0.1:8765" "$logs"
assert_not_contains "password not in logs" "$LOCAL_PASSWORD" "$logs"
# shellcheck disable=SC2016  # a bcrypt prefix, not a shell expansion
assert_not_contains "password hash not in logs" '\$2a\$' "$logs"

section "anonymous visitors are refused"
# Spoolman has no authentication of its own: without the front door every one of these succeeds.
assert_eq "web interface refused" "401" "$(http_code "$BASE_URL/")"
assert_eq "spool list refused" "401" "$(http_code "$BASE_URL/api/v1/spool")"
assert_eq "vendor list refused" "401" "$(http_code "$BASE_URL/api/v1/vendor")"
assert_eq "instance info refused" "401" "$(http_code "$BASE_URL/api/v1/info")"
assert_eq "backup endpoint refused" "401" "$(http_code -X POST "$BASE_URL/api/v1/backup")"
assert_eq "writes refused" "401" "$(http_code -X POST "$BASE_URL/api/v1/vendor" -H 'Content-Type: application/json' --data '{"name":"Intruder"}')"
assert_eq "wrong password refused" "401" "$(http_code -u "admin:wrong-password-entirely" "$BASE_URL/api/v1/spool")"
assert_eq "wrong username refused" "401" "$(http_code -u "nobody:$LOCAL_PASSWORD" "$BASE_URL/api/v1/spool")"
assert_eq "health route stays open for the platform probe" "200" "$(http_code "$BASE_URL/api/v1/health")"
assert_eq "health route leaks nothing but a status" '{"status":"healthy"}' "$(curl -s --max-time 20 "$BASE_URL/api/v1/health")"

section "the app is not reachable except through the front door"
# curl still prints 000 through -w when it cannot connect, so `|| true` rather than `|| echo`
assert_eq "internal port is not published" "000" "$(http_code --max-time 5 "http://127.0.0.1:8765/api/v1/health" || true)"
listeners=$(compose exec -T spoolman python3 -c "
import socket
for port in (8000, 8765):
    for fam, addr in ((socket.AF_INET,'0.0.0.0'),):
        s = socket.socket(fam, socket.SOCK_STREAM)
        try:
            s.bind((addr, port)); print(f'{port} free')
        except OSError:
            print(f'{port} taken')
        finally:
            s.close()
" 2>/dev/null || echo "")
assert_contains "public port is bound inside the container" "8000 taken" "$listeners"

section "authenticated workflow: vendor, filament, spool, usage"
assert_eq "web interface served" "200" "$(auth_code "$BASE_URL/")"
i=$(info)
assert_eq "version reported" "0.26.1" "$(jq -r .version <<<"$i")"
assert_eq "sqlite backend" "sqlite" "$(jq -r .db_type <<<"$i")"
V=$(create_vendor "Smoke Filaments"); [ -n "$V" ] && pass "vendor created (id $V)" || die "vendor create failed"
F=$(create_filament "$V" "Smoke PLA" "PLA"); [ -n "$F" ] && pass "filament created (id $F)" || die "filament create failed"
S=$(create_spool "$F"); [ -n "$S" ] && pass "spool created (id $S)" || die "spool create failed"
s=$(spool_json "$S")
assert_eq "spool starts full" "1000" "$(jq -r '.remaining_weight | floor' <<<"$s")"
assert_eq "filament linked" "Smoke PLA" "$(jq -r '.filament.name' <<<"$s")"
assert_eq "vendor linked" "Smoke Filaments" "$(jq -r '.filament.vendor.name' <<<"$s")"
use_filament "$S" 250 >/dev/null
s=$(spool_json "$S")
assert_eq "usage subtracted" "750" "$(jq -r '.remaining_weight | floor' <<<"$s")"
assert_eq "used weight recorded" "250" "$(jq -r '.used_weight | floor' <<<"$s")"
assert_eq "spool listed" "1" "$(jq -r 'length' <<<"$(spools)")"

section "graceful shutdown (SIGTERM)"
t1=$(date +%s); compose stop -t 30 spoolman; dur=$(( $(date +%s)-t1 ))
code=$(docker inspect --format '{{.State.ExitCode}}' "$(compose ps -a -q spoolman)")
[ "$dur" -lt 30 ] && pass "stopped in ${dur}s without SIGKILL" || fail "stop took ${dur}s"
case "$code" in 0|143) pass "exit status after SIGTERM is $code" ;; *) fail "unexpected exit status $code" ;; esac
compose start spoolman; wait_for_code "$BASE_URL/api/v1/health" 200 300 && pass "restarted" || die "did not restart"
assert_eq "data survived the restart" "750" "$(jq -r '.remaining_weight | floor' <<<"$(spool_json "$S")")"

section "fail-fast validation"
img=$(compose config --images | head -1)
run_img() { docker run --rm "$@" "$img" >"$TEST_TMP/ff.log" 2>&1; }
if run_img; then fail "should fail without a password"; else pass "exits without SPOOLMAN_AUTH_PASSWORD"; fi
assert_contains "explains why a password is required" "anyone who finds the URL can read and edit" "$(cat "$TEST_TMP/ff.log")"
if run_img -e SPOOLMAN_AUTH_PASSWORD=short; then fail "should reject a short password"; else pass "rejects a short password"; fi
assert_contains "states the length rule" "at least 12 characters" "$(cat "$TEST_TMP/ff.log")"
if run_img -e "SPOOLMAN_AUTH_PASSWORD=$LOCAL_PASSWORD" -e SPOOLMAN_HOST=0.0.0.0; then fail "should refuse to unbind from loopback"; else pass "refuses a non-loopback SPOOLMAN_HOST"; fi
assert_contains "explains the loopback rule" "publish a writable database" "$(cat "$TEST_TMP/ff.log")"
if run_img -e "SPOOLMAN_AUTH_PASSWORD=$LOCAL_PASSWORD" -e PORT=8765; then fail "should refuse a port collision"; else pass "refuses a port collision with the app"; fi
assert_contains "explains the collision" "cannot share a port" "$(cat "$TEST_TMP/ff.log")"
assert_not_contains "no secret echoed" "$LOCAL_PASSWORD" "$(cat "$TEST_TMP/ff.log")"

section "the opt-out is deliberate and loud"
docker rm -f spool-open >/dev/null 2>&1 || true
docker run -d --name spool-open -e SPOOLMAN_ALLOW_PUBLIC=true -e PORT=8010 -p 127.0.0.1:8010:8010 "$img" >/dev/null
for _ in $(seq 1 60); do [ "$(http_code --max-time 5 "http://127.0.0.1:8010/api/v1/health" || echo 000)" = "200" ] && break; sleep 3; done
assert_eq "open instance serves anonymously" "200" "$(http_code "http://127.0.0.1:8010/api/v1/spool")"
assert_contains "and says so in the log" "Authentication is disabled" "$(docker logs spool-open 2>&1)"
docker rm -f spool-open >/dev/null

section "image metadata"
assert_eq "architecture" "amd64" "$(docker image inspect "$img" --format '{{.Architecture}}')"
labels=$(docker image inspect "$img" --format '{{json .Config.Labels}}')
for l in org.opencontainers.image.source org.opencontainers.image.revision org.opencontainers.image.version io.spoolman-railway.upstream.version io.spoolman-railway.caddy.version; do
  assert_contains "label $l" "\"$l\"" "$labels"
done
assert_contains "upstream licence shipped" "MIT License" "$(compose exec -T spoolman head -1 /usr/share/licenses/spoolman-railway/SPOOLMAN-LICENSE | tr -d '\r')"
assert_contains "Caddy licence shipped" "Apache License" "$(compose exec -T spoolman sed -n '2p' /usr/share/licenses/spoolman-railway/CADDY-LICENSE | tr -d '\r')"

section "metrics"
{ echo "image_bytes=$(docker image inspect "$img" --format '{{.Size}}')"
  docker stats --no-stream --format '{{.Name}} mem={{.MemUsage}}' | grep spoolman-railway-test | sed 's/^/mem_/'; } | tee -a "$METRICS"
summary
