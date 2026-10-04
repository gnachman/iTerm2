#!/bin/bash
# Manual check that the shells shipped with macOS accept the argument shapes
# iTermShellArguments produces (see pidinfo/iTermShellArguments.m). Run after
# changing that table. Uses a scratch HOME so your own startup files stay out
# of it; the system /etc files still run, which is why this is not a unit test.
#
#   tests/check_shell_arguments.sh
#
# Expect “ok” for every line. tcsh and csh are expected to fail the -l shape,
# which is why the table gives them -i -c instead.

set -u
home=$(mktemp -d)
trap 'rm -rf "$home"' EXIT
printf 'exit 0\n' > "$home/script"
chmod 700 "$home/script"

status=0
check() {
    local shell=$1; shift
    if env -i HOME="$home" PATH=/usr/bin:/bin "$shell" "$@" "$home/script" </dev/null >/dev/null 2>&1; then
        echo "ok    $shell $*"
    else
        echo "FAIL  $shell $* (exit $?)"
        status=1
    fi
}

for shell in /bin/zsh /bin/bash /bin/sh /bin/dash /bin/ksh; do
    check "$shell" -l -i -c
    check "$shell" -i -c
    check "$shell" -c
done
for shell in /bin/tcsh /bin/csh; do
    check "$shell" -i -c
    check "$shell" -c
    echo "(expected to fail) $(env -i HOME="$home" "$shell" -l -i -c "$home/script" </dev/null 2>&1 | head -1)"
done
for shell in /opt/homebrew/bin/fish /usr/local/bin/fish; do
    [ -x "$shell" ] && check "$shell" -l -i -c
done
exit $status
