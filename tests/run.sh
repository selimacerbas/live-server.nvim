#!/bin/sh
# The one test loop CI and `make test` share: every suite runs even after one
# fails, so a red run names them all; the help tags are checked when a doc/
# directory exists. Neovim opens its startup log under XDG_STATE_HOME before
# any script runs, the one path the helper cannot move, so a caller's exported
# value is honoured and otherwise one fixed directory under TMPDIR is reused.
set -u
cd "$(dirname "$0")/.." || exit 1
export XDG_STATE_HOME="${XDG_STATE_HOME:-${TMPDIR:-/tmp}/nvim-plugin-tests-state}"
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
