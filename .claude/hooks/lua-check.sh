#!/usr/bin/env bash
# PostToolUse (Edit|Write on *.lua): the CI's syntax check (luac -p under Lua 5.1) on the edited
# file, then luacheck when the repo has a .luacheckrc. Exit 2 shows the error to Claude.
# Embedded libs/ are skipped, as in .github/workflows/tests.yml.
# Vendored from Ciaanh/wow-dev (repo-slice/); edit it there and sync, not here.
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
INPUT=$(cat)
LUA=$(find_lua) || exit 0

file=$(json_get tool_input.file_path)
[ -n "$file" ] || exit 0
file=$(physical "$(to_posix "$file")")
case "$file" in *.lua) ;; *) exit 0 ;; esac
[ -f "$file" ] || exit 0
in_project "$file" || exit 0
root=$(repo_root "$(dirname "$file")") || exit 0
rel=${file#"$root"/}
case "$(printf '%s' "$rel" | tr '[:upper:]' '[:lower:]')" in libs/* | */libs/*) exit 0 ;; esac

mark_dirty "$root"

if LUAC=$(find_luac); then
    if ! out=$("$LUAC" -p "$(to_native "$file")" 2>&1); then
        printf 'luac (Lua 5.1, as the CI runs it) rejects %s:\n%s\n' "$rel" "$out" >&2
        exit 2
    fi
fi

# No pcall / xpcall in addon code: errors stay explicit so BugSack shows each one with its stack.
# Test suites may use them to assert that a call raises, and dot-directories (.claude/, .github/)
# hold tooling, not addon code. Comments are ignored.
case "$(printf '%s' "$rel" | tr '[:upper:]' '[:lower:]')" in
    tests/* | */tests/* | .* | */.*) ;;
    *)
        hits=$(awk '
            {
                line = $0; out = ""
                while (line != "") {
                    if (inblock) {
                        p = index(line, "]]"); if (!p) { line = ""; break }
                        line = substr(line, p + 2); inblock = 0; continue
                    }
                    p = index(line, "--"); if (!p) { out = out line; break }
                    out = out substr(line, 1, p - 1); rest = substr(line, p + 2)
                    if (rest ~ /^\[=*\[/) { inblock = 1; line = substr(rest, 2) } else break
                }
                if (out ~ /(^|[^A-Za-z0-9_.:])x?pcall[ \t]*\(/) printf "%d: %s\n", NR, $0
            }' "$file")
        if [ -n "$hits" ]; then
            printf '%s calls pcall/xpcall, which addon code must not do (errors stay explicit for BugSack).\nTest for what may be missing instead (`if C_Foo and C_Foo.Bar then`, the capability probe):\n%s\n' \
                "$rel" "$(printf '%s\n' "$hits" | head -20)" >&2
            exit 2
        fi
        ;;
esac

if [ -f "$root/.luacheckrc" ] && LC=$(find_luacheck); then
    if ! out=$(cd "$root" && "$LC" --no-color --codes --formatter plain "$rel" 2>&1); then
        printf 'luacheck on %s:\n%s\n' "$rel" "$(printf '%s\n' "$out" | head -40)" >&2
        exit 2
    fi
fi
exit 0
