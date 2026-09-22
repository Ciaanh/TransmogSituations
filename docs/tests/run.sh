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

echo "-- tests --"
for t in replay_retail replay_retail_loadouts replay_forever replay_forever_viewed          resolvers equipment_sets cache_invalidation attach_retry list_marking eligibility; do
    run "$t" "docs/tests/$t.lua" .
done

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES"
exit $fail
