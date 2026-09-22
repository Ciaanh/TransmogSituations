#!/usr/bin/env bash
# Runs the whole suite. Usage, from the repo root:  ./docs/tests/run.sh
set -u

LUA=${LUA:-"/c/Program Files (x86)/Lua/5.1/lua.exe"}
LUAC=${LUAC:-"/c/Program Files (x86)/Lua/5.1/luac.exe"}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT" || exit 1

fail=0

echo "-- syntax --"
for f in core/*.lua BetterSituation.lua; do
    if "$LUAC" -p "$f" 2>/dev/null; then
        printf '  %-34s OK\n' "$f"
    else
        printf '  %-34s FAIL\n' "$f"; fail=1
    fi
done

run() {
    local label=$1; shift
    if out=$("$LUA" "$@" 2>&1); then
        printf '  %-34s OK\n' "$label"
    else
        printf '  %-34s FAIL\n' "$label"; echo "$out" | sed 's/^/      /'; fail=1
    fi
}

echo "-- replays of real captures --"
run "retail"  docs/tests/replay_retail.lua .
run "retail, loadouts + outfit viewed" docs/tests/replay_retail_loadouts.lua .
run "forever" docs/tests/replay_forever.lua .
run "forever, outfit viewed" docs/tests/replay_forever_viewed.lua .

echo "-- resolver branches --"
run "all branches" docs/tests/resolvers.lua .

echo "-- category cache --"
run "invalidation" docs/tests/cache_invalidation.lua .

echo "-- attach lifecycle --"
run "retry until the frame exists" docs/tests/attach_retry.lua .

echo "-- /bs list marking --"
run "current + also active" docs/tests/list_marking.lua .

echo "-- phase 4: cache + eligibility --"
run "match, rank, verify" docs/tests/eligibility.lua .

echo "-- equipment sets --"
for s in equipped distinct allequipped tiebreak specassigned swappedring partial idmismatch; do
    run "$s" docs/tests/equipment_sets.lua . "$s"
done

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES"
exit $fail
