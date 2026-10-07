#!/bin/zsh
# Run a Python API script against the -suite development instance of iTerm2, never the main app.
#
#   tests/floating_panes/devapi.sh script.py [args...]
#
# The suite defaults to the name of the checkout's directory, which is what `make run` uses.
# Override it with SUITE=name. The dev instance must have the Python API enabled.

set -e
here=${0:A:h}
repo=${here:h:h}
suite=${SUITE:-${repo:t}}
devctl=${TMPDIR:-/tmp}/iterm2-devctl-$USER

if [[ ! -x $devctl || $here/devctl.swift -nt $devctl ]]; then
    swiftc -O $here/devctl.swift -o $devctl
fi

pid=$($devctl devpid $suite)
credentials=(${(z)$($devctl cookie $pid)})
IT2_SUITE=$suite ITERM2_COOKIE=$credentials[1] ITERM2_KEY=$credentials[2] exec python3 "$@"
