#!/bin/bash
# Live it2-over-ssh-integration harness. Runs SSHIntegrationLiveHarness in the ModernTests bundle
# against `ssh localhost`. NOT a unit test: it opens real windows, runs the real conductor
# bootstrap and framer over a real ssh connection, and runs the uploaded it2 on this Mac as the
# remote host. Outside the default ModernTests run, which skips it.
#
# Requires Remote Login (System Settings > General > Sharing) and key-based ssh to localhost:
#   ssh -o BatchMode=yes localhost true
#
# Side effects: ssh integration uploads it2 under ~/.iterm2 as on any host. ~/.iterm2/it2-grant is
# backed up and restored. Mac-side grants go to an in-memory store, not your settings.
#
# Usage:
#   tools/run_ssh_integration_live.sh                 # everything
#   tools/run_ssh_integration_live.sh <TestMethodName>
#       e.g. testTwoHops, testAlwaysAllowSurvivesReconnectUntilRevoked

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if ! ssh -o BatchMode=yes -o ConnectTimeout=5 localhost true 2>/dev/null; then
    echo "ssh -o BatchMode=yes localhost true failed. Turn on Remote Login and key-based ssh to localhost." >&2
    exit 2
fi

class_path="ModernTests/SSHIntegrationLiveHarness"
if [[ -n "${1:-}" ]]; then
    target="${class_path}/$1"
else
    target="$class_path"
fi

# xcodebuild's test runner does not inherit the environment. The TEST_RUNNER_ prefix forwards
# this into the test process, where the harness reads ITERM2_SSH_LIVE to opt in.
export TEST_RUNNER_ITERM2_SSH_LIVE=1

cd "$PROJECT_DIR"
echo "Running live ssh integration harness: $target"
exec tools/run_tests.expect "$target"
