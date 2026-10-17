# common.sh: sourced by this repo's Claude Code hooks (.claude/hooks/*.sh).
# Vendored from Ciaanh/wow-dev (repo-slice/); edit it there and sync, not here.
# Every hook fails open: a missing tool or an unreadable input means exit 0.

HOOKS=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# to_native / to_posix: Windows (Git Bash) path forms; unchanged on Linux.
to_native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
to_posix()  { if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s' "$1"; fi; }

first_command() {
    local c
    for c in "$@"; do
        [ -n "$c" ] || continue
        if command -v "$c" >/dev/null 2>&1; then printf '%s' "$c"; return 0; fi
    done
    return 1
}

# Lua 5.1, as tests/run.sh and the CI use it (LUA= / LUAC= override, like tests/run.sh).
find_lua()  { first_command "${LUA:-}" lua5.1 lua lua.exe "/c/Program Files (x86)/Lua/5.1/lua.exe"; }
find_luac() {
    local c
    c=$(first_command "${LUAC:-}" luac5.1 "/c/Program Files (x86)/Lua/5.1/luac.exe") && { printf '%s' "$c"; return 0; }
    command -v luac >/dev/null 2>&1 && luac -v 2>&1 | grep -q 'Lua 5\.1' && { printf 'luac'; return 0; }
    return 1
}
find_luacheck() { first_command "${LUACHECK:-}" luacheck luacheck.bat luacheck.exe; }

# json_get PATH: the value at PATH in the hook input held in $INPUT.
json_get() { printf '%s' "$INPUT" | "$LUA" "$(to_native "$HOOKS/lib/json-get.lua")" "$1"; }

# The repo's top folder, as a bash path.
repo_root() {
    local top
    top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
    to_posix "$top"
}

# This session's project directory; hooks only handle files under it (the wow-dev plugin covers
# the others, so nothing runs twice).
in_project() {
    local proj
    proj=$(to_posix "${CLAUDE_PROJECT_DIR:-$(pwd)}")
    case "$1" in "$proj"/*) return 0 ;; *) return 1 ;; esac
}

# The per-worktree marker listing the sessions that edited Lua since the last green suite.
marker() { printf '%s/wow-dev-dirty' "$(to_posix "$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null)")"; }

mark_dirty() { # repo root
    local m sid
    sid=$(json_get session_id)
    [ -n "$sid" ] || return 0
    m=$(marker "$1")
    grep -qxF "$sid" "$m" 2>/dev/null || printf '%s\n' "$sid" >> "$m"
}
