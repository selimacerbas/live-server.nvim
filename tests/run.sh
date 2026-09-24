#!/bin/sh
# The one test loop CI and `make test` share: every suite runs even after one
# fails, so a red run names them all; the help tags are checked when a doc/
# directory exists. Neovim opens its startup log under XDG_STATE_HOME before
# any script runs, the one path the helper cannot move, so a caller's exported
# value is honoured and otherwise a directory private to this user under TMPDIR
# is reused. The run refuses that path unless it is a real directory this user
# owns: in a shared /tmp another account can create it first, and an unwritable
# one made Neovim log into the repository root (measured). A symbolic link is
# refused before the -d and -O tests, which follow it: its creator can repoint
# it after the check (measured). In a sticky directory such as /tmp a real
# directory this user owns cannot be renamed or replaced by another account.
set -u
cd "$(dirname "$0")/.." || exit 1
if [ -z "${XDG_STATE_HOME:-}" ]; then
    XDG_STATE_HOME="${TMPDIR:-/tmp}/nvim-plugin-tests-state-$(id -u)"
    mkdir -p -m 700 "$XDG_STATE_HOME"
    if [ -L "$XDG_STATE_HOME" ]; then
        echo "tests/run.sh: $XDG_STATE_HOME is a symbolic link; refusing to run" >&2
        exit 1
    fi
    if [ ! -d "$XDG_STATE_HOME" ] || [ ! -O "$XDG_STATE_HOME" ]; then
        echo "tests/run.sh: $XDG_STATE_HOME is not a directory this user owns; refusing to run" >&2
        exit 1
    fi
fi
export XDG_STATE_HOME
fail=0
for t in tests/*_test.lua; do
    [ -n "${GITHUB_ACTIONS:-}" ] && printf '::group::%s\n' "$t"
    nvim --headless -u NONE -l "$t" || fail=1
    [ -n "${GITHUB_ACTIONS:-}" ] && printf '::endgroup::\n'
done
if [ -d doc ]; then
    nvim --headless -u NONE -c 'try | helptags doc | catch | echomsg v:exception | cquit 1 | endtry' -c 'qa!' || fail=1
fi
exit "$fail"
