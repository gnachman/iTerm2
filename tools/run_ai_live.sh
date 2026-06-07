#!/bin/bash
# Live AI test harness runner. Drives AILiveHarness in the ModernTests
# bundle against real vendor APIs. Costs real money. NOT a unit test.
#
# Usage:
#   tools/run_ai_live.sh                  # every harness method
#   tools/run_ai_live.sh openai           # all OpenAI tests
#   tools/run_ai_live.sh smoke            # smoke across vendors
#   tools/run_ai_live.sh test_openai_smoke_streaming  # exact method
#
# Reads API keys from the environment:
#   OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY DEEPSEEK_API_KEY
#
# Vendors with no key set are skipped automatically by the harness.
#
# By default the harness exercises every model in AIMetadata.swift for
# each vendor with a key. For a faster sweep, set per-vendor model lists
# via env vars before invoking this script:
#
#   ITERM2_AI_LIVE_OPENAI_MODELS=gpt-5,gpt-5-mini tools/run_ai_live.sh smoke
#
# Refusal scenarios write captured responses to
# ModernTests/Resources/SafetyRefusalFixtures/ only when explicitly
# requested. Set ITERM2_AI_LIVE_REFRESH_REFUSAL_FIXTURES=1 to refresh.
# Without it, refusal runs exercise the API path but leave the on-disk
# fixtures untouched so casual sweeps don't dirty the working tree.
#
# Why a JSON file: xcodebuild's test runner does not inherit shell env
# vars, so this script writes a JSON config to a temp file and the
# harness reads from there. The file is mode 0600, lives under
# $TMPDIR, and is removed on script exit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
# Write the config to /tmp explicitly. macOS's per-user $TMPDIR under
# /var/folders/.../T/ has a periodic cleanup that races with long test
# sweeps: with 96 test cases the run takes ~70s and the cleanup deletes
# the config file mid-sweep, after which every remaining test XCTSkip's
# with "Live AI harness is opt-in." /tmp doesn't have that rotation.
CONFIG_FILE="/tmp/iterm2-ai-live.json"

cleanup() {
    rm -f "$CONFIG_FILE"
}
# Only clean up on signal-driven exit (Ctrl-C, kill). The normal-exit
# trap was racing with xcodebuild's test process: long sweeps that pass
# many -only-testing flags take long enough to start the test process
# that the trap (which fires on bash exec replacement on some systems)
# would delete the config before AILiveHarness.setUpWithError could
# read it. Result: every test in the long sweep XCTSkip'd with
# "Live AI harness is opt-in". The config file is harmless to leave
# behind in $TMPDIR/iterm2-ai-live.json and macOS rotates that
# directory on reboot.
trap cleanup INT TERM HUP

# JSON-quote a value for safe embedding (handles backslash and quote).
json_quote() {
    printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
}

# Build the config file. Only set fields whose source value is non-empty.
{
    echo "{"
    first=1
    emit() {
        local key="$1" value="$2"
        [[ -z "$value" ]] && return
        if [[ $first -eq 1 ]]; then
            first=0
        else
            echo ","
        fi
        printf '  %s: %s' "$(json_quote "$key")" "$(json_quote "$value")"
    }
    emit OPENAI_API_KEY    "${OPENAI_API_KEY:-}"
    emit ANTHROPIC_API_KEY "${ANTHROPIC_API_KEY:-}"
    emit GEMINI_API_KEY    "${GEMINI_API_KEY:-}"
    emit DEEPSEEK_API_KEY  "${DEEPSEEK_API_KEY:-}"
    emit OPENAI_MODELS      "${ITERM2_AI_LIVE_OPENAI_MODELS:-}"
    emit ANTHROPIC_MODELS   "${ITERM2_AI_LIVE_ANTHROPIC_MODELS:-}"
    emit GEMINI_MODELS      "${ITERM2_AI_LIVE_GEMINI_MODELS:-}"
    emit DEEPSEEK_MODELS    "${ITERM2_AI_LIVE_DEEPSEEK_MODELS:-}"
    emit OPENAI_INTERVAL    "${ITERM2_AI_LIVE_OPENAI_INTERVAL:-}"
    emit ANTHROPIC_INTERVAL "${ITERM2_AI_LIVE_ANTHROPIC_INTERVAL:-}"
    emit GEMINI_INTERVAL    "${ITERM2_AI_LIVE_GEMINI_INTERVAL:-}"
    emit DEEPSEEK_INTERVAL  "${ITERM2_AI_LIVE_DEEPSEEK_INTERVAL:-}"
    emit PROJECT_ROOT       "$PROJECT_DIR"
    emit REFRESH_REFUSAL_FIXTURES "${ITERM2_AI_LIVE_REFRESH_REFUSAL_FIXTURES:-}"
    # Cassette record/playback. Unset means pure-live (the historical
    # behavior). See AICassette.swift for the mode semantics.
    #   off     no interception (default when unset)
    #   auto    replay on hit, go live + record on miss
    #   replay  replay on hit, fail offline on miss (CI; spends nothing)
    #   record  always go live and (over)write the cassette (refresh)
    # Cassettes default to ModernTests/Resources/AICassettes and are
    # scrubbed of secrets, so they are safe to commit.
    emit CASSETTE_MODE      "${ITERM2_AI_LIVE_CASSETTE_MODE:-}"
    emit CASSETTE_DIR       "${ITERM2_AI_LIVE_CASSETTE_DIR:-}"
    echo
    echo "}"
} > "$CONFIG_FILE"
chmod 0600 "$CONFIG_FILE"

# Resolve the filter argument to one or more -only-testing flags.
filter="${1:-}"
class_path="ModernTests/AILiveHarness"

if [[ -z "$filter" ]]; then
    only_testing_args=( "$class_path" )
elif [[ "$filter" == test_* ]]; then
    only_testing_args=( "${class_path}/${filter}" )
else
    # Discover test methods from AILiveHarness source files at script time.
    # Previously this list was hardcoded, which meant new test files (e.g.
    # AILiveAttachmentTests.swift with the 96-cell matrix) didn't show up
    # for substring filtering until the list was manually updated.
    methods=()
    while IFS= read -r m; do
        [[ -n "$m" ]] && methods+=( "$m" )
    done < <(grep -h -E '^\s*func test_[A-Za-z0-9_]+\(' "$PROJECT_DIR"/AILiveHarness/*.swift \
             | sed -E 's/^[[:space:]]*func (test_[A-Za-z0-9_]+).*/\1/' \
             | sort -u)
    matched=()
    for m in "${methods[@]}"; do
        if [[ "$m" == *"$filter"* ]]; then
            matched+=( "${class_path}/${m}" )
        fi
    done
    if [[ ${#matched[@]} -eq 0 ]]; then
        echo "No method names matched '$filter'." >&2
        echo "Pass 'openai', 'anthropic', 'gemini', 'deepseek', a scenario like 'smoke', or an exact test name." >&2
        exit 2
    fi
    only_testing_args=( "${matched[@]}" )
fi

cd "$PROJECT_DIR"
# Tell run_tests.expect to leave the config file alone — it's the live
# invocation marker for AILiveHarness's setUpWithError. Plain ModernTests
# runs default to deleting stale configs, which is what we want for them.
export ITERM2_AI_LIVE_KEEP_CONFIG=1
# Don't `exec` here: bash needs to live long enough for the EXIT trap
# above to fire and remove $CONFIG_FILE after the tests finish. An
# `exec` would replace bash with run_tests.expect, dropping the trap
# and leaking the config file (the very stale-state bug the cleanup in
# run_tests.expect is there to catch).
tools/run_tests.expect "${only_testing_args[@]}"
