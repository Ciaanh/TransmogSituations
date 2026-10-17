#!/usr/bin/env bash
# Stop: when this session edited Lua here since the suite last passed, run tests/run.sh before
# the turn ends. On failure exit 2: Claude gets the failing lines and keeps working. Runs once
# per turn (stop_hook_active), so Claude can still stop and explain a failure it cannot fix.
# Vendored from Ciaanh/wow-dev (repo-slice/); edit it there and sync, not here.
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
INPUT=$(cat)
LUA=$(find_lua) || exit 0
[ "$(json_get stop_hook_active)" = "true" ] && exit 0

root=$(repo_root "$(to_posix "${CLAUDE_PROJECT_DIR:-$(pwd)}")") || exit 0
[ -f "$root/tests/run.sh" ] || exit 0
sid=$(json_get session_id)
m=$(marker "$root")
[ -n "$sid" ] && grep -qxF "$sid" "$m" 2>/dev/null || exit 0

export LUA
LUAC=$(find_luac) && export LUAC
if out=$(cd "$root" && bash tests/run.sh 2>&1); then
    grep -vxF "$sid" "$m" > "$m.tmp" 2>/dev/null; mv -f "$m.tmp" "$m"
    exit 0
fi
{
    printf 'tests/run.sh fails in %s after this session'"'"'s Lua edits. Fix it before finishing, or say why not:\n' "$(basename "$root")"
    printf '%s\n' "$out" | grep -v ' OK$' | tail -60
} >&2
exit 2
