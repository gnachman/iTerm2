#!/bin/bash
# Live shell-integration test harness runner. Drives
# ShellIntegrationLiveHarness in the ModernTests bundle against real
# shells (zsh, bash, fish, tcsh, xonsh). NOT a unit test — it spawns
# subprocesses and reads from a pseudo-tty.
#
# Usage:
#   tools/run_shell_integration_live.sh                 # all shells
#   tools/run_shell_integration_live.sh zsh             # one shell only
#   tools/run_shell_integration_live.sh test_zsh_baseline_singleCommandEmitsOneInitialPrompt
#
# Shells that aren't installed are skipped automatically by the harness.
#
# Why a JSON file: xcodebuild's test runner does not inherit shell env
# vars, so this script writes a JSON config to a temp file and the
# harness reads from there. The file is mode 0600, lives under
# $TMPDIR, and is removed on script exit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TMPDIR_BASE="${TMPDIR:-/tmp}"
CONFIG_FILE="$(printf '%s/%s' "${TMPDIR_BASE%/}" iterm2-shell-integration-live.json)"

cleanup() {
    rm -f "$CONFIG_FILE"
}
trap cleanup EXIT

# JSON-quote a value for safe embedding (handles backslash and quote).
json_quote() {
    printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
}

cat > "$CONFIG_FILE" <<EOF
{
  $(json_quote PROJECT_ROOT): $(json_quote "$PROJECT_DIR")
}
EOF
chmod 0600 "$CONFIG_FILE"

# Resolve the filter argument to one or more -only-testing flags.
filter="${1:-}"
class_path="ModernTests/ShellIntegrationLiveHarness"

if [[ -z "$filter" ]]; then
    only_testing_args=( "$class_path" )
elif [[ "$filter" == test_* ]]; then
    only_testing_args=( "${class_path}/${filter}" )
else
    # Treat as a shell name (zsh, bash, fish, tcsh, xonsh).
    case "$filter" in
        zsh|bash|fish|tcsh|xonsh)
            # Match all tests whose method name starts with the capitalized shell name.
            cap="$(tr '[:lower:]' '[:upper:]' <<< "${filter:0:1}")${filter:1}"
            methods=(
                "test${cap}_baseline_emitsOnePromptAPerCommand"
            )
            only_testing_args=()
            for m in "${methods[@]}"; do
                only_testing_args+=( "${class_path}/${m}" )
            done
            ;;
        *)
            echo "Unknown filter '$filter'. Pass a shell name (zsh/bash/fish/tcsh/xonsh) or an exact test method name." >&2
            exit 2
            ;;
    esac
fi

cd "$PROJECT_DIR"
# Tell run_tests.expect to leave the config file alone (it's the live
# invocation marker for ShellIntegrationLiveHarness's setUpWithError).
export ITERM2_SHELL_INTEGRATION_LIVE_KEEP_CONFIG=1
tools/run_tests.expect "${only_testing_args[@]}"
