#!/usr/bin/env bash
# PostToolUse (Edit|Write on *.toc): every file the toc lists exists, and every Lua file under a
# folder make-release.ps1 ships is loaded by a toc or an xml. Exit 2 shows the problems to Claude.
# Vendored from Ciaanh/wow-dev (repo-slice/); edit it there and sync, not here.
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
INPUT=$(cat)
LUA=$(find_lua) || exit 0

file=$(json_get tool_input.file_path)
[ -n "$file" ] || exit 0
file=$(to_posix "$file")
case "$file" in *.toc) ;; *) exit 0 ;; esac
[ -f "$file" ] || exit 0
in_project "$file" || exit 0
root=$(repo_root "$(dirname "$file")") || exit 0

out=$(cd "$root" && git ls-files --cached --others --exclude-standard -- '*.lua' '*.xml' '*.toc' |
    "$LUA" "$(to_native "$HOOKS/lib/toc-check.lua")" "$(to_native "$root")")
if [ -n "$out" ]; then
    printf '%s\n' "$out" >&2
    exit 2
fi
exit 0
