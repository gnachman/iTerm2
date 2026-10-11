#!/bin/bash
# Live harness for tmux workgroup concurrency. Runs TmuxWorkgroupLiveHarness in the ModernTests
# bundle: a private tmux server (its own socket, no config file) with two control-mode clients,
# each driven by a real TmuxGateway, racing guarded peer switches and the per-session lock. NOT a
# unit test; outside the default ModernTests run, which skips it.
#
# With --e2e it instead runs TmuxWorkgroupEndToEndHarness: a real session attaches with tmux -CC,
# so the test host runs real tmux Integration (TmuxController, tabs, workgroup instances). It opens
# windows in the test host, so it also requires ITERM2_ONSCREEN_TESTS=1 in the caller's
# environment, as any test that puts windows on screen does.
#
# Usage:
#   tools/run_tmux_workgroup_live.sh [--tmux /path/to/tmux] [TestMethodName]
#   ITERM2_ONSCREEN_TESTS=1 tools/run_tmux_workgroup_live.sh --e2e [--tmux /path/to/tmux] [TestMethodName]
#
# Run it against the oldest supported tmux (3.2), one before 3.8, and 3.8 or later: members are
# relaunched differently from 3.8 on (TmuxWorkgroupCommands.RelaunchMethod). E.g. a 3.2a built
# from its release tag:
#   git clone https://github.com/tmux/tmux && cd tmux && git checkout 3.2a && sh autogen.sh &&
#   ./configure && make

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

class_path="ModernTests/TmuxWorkgroupLiveHarness"
if [[ "${1:-}" == "--e2e" ]]; then
    class_path="ModernTests/TmuxWorkgroupEndToEndHarness"
    if [[ "${ITERM2_ONSCREEN_TESTS:-}" != "1" ]]; then
        echo "--e2e opens windows. Run it with ITERM2_ONSCREEN_TESTS=1 $0 $*" >&2
        exit 2
    fi
    export TEST_RUNNER_ITERM2_TMUX_E2E=1
    export TEST_RUNNER_ITERM2_ONSCREEN_TESTS=1
    shift
fi

tmux_path="$(command -v tmux || true)"
if [[ "${1:-}" == "--tmux" ]]; then
    tmux_path="$2"
    shift 2
fi
if [[ -z "$tmux_path" || ! -x "$tmux_path" ]]; then
    echo "No tmux found. Pass --tmux /path/to/tmux." >&2
    exit 2
fi
echo "Using $("$tmux_path" -V) at $tmux_path"

if [[ -n "${1:-}" ]]; then
    target="${class_path}/$1"
else
    target="$class_path"
fi

# xcodebuild's test runner does not inherit the environment. The TEST_RUNNER_ prefix forwards
# these into the test process.
export TEST_RUNNER_ITERM2_TMUX_LIVE=1
export TEST_RUNNER_ITERM2_TMUX_PATH="$tmux_path"

cd "$PROJECT_DIR"
echo "Running live tmux workgroup harness: $target"
exec tools/run_tests.expect "$target"
