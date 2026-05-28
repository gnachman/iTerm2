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
# Honor TMPDIR with or without a trailing slash; fall back to /tmp.
TMPDIR_BASE="${TMPDIR:-/tmp}"
CONFIG_FILE="$(printf '%s/%s' "${TMPDIR_BASE%/}" iterm2-ai-live.json)"

cleanup() {
    rm -f "$CONFIG_FILE"
}
trap cleanup EXIT

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
    methods=(
        test_openai_smoke_nonStreaming
        test_openai_smoke_streaming
        test_openai_multiTurn_nonStreaming
        test_openai_multiTurn_streaming
        test_openai_toolCall_nonStreaming
        test_openai_toolCall_streaming
        test_openai_chatCompletions_smoke_nonStreaming
        test_openai_chatCompletions_smoke_streaming
        test_openai_chatCompletions_multiTurn_nonStreaming
        test_openai_chatCompletions_multiTurn_streaming
        test_openai_chatCompletions_toolCall_nonStreaming
        test_openai_chatCompletions_toolCall_streaming
        test_openai_legacyCompletions_smoke_nonStreaming
        test_anthropic_smoke_nonStreaming
        test_anthropic_smoke_streaming
        test_anthropic_multiTurn_nonStreaming
        test_anthropic_multiTurn_streaming
        test_anthropic_toolCall_nonStreaming
        test_anthropic_toolCall_streaming
        test_anthropic_refusal_nonStreaming
        test_anthropic_refusal_streaming
        test_anthropic_imageDescribe
        test_gemini_smoke_nonStreaming
        test_gemini_smoke_streaming
        test_gemini_multiTurn_nonStreaming
        test_gemini_multiTurn_streaming
        test_gemini_toolCall_nonStreaming
        test_gemini_toolCall_streaming
        test_gemini_refusal_nonStreaming
        test_gemini_refusal_streaming
        test_gemini_imageDescribe
        test_deepseek_smoke_nonStreaming
        test_deepseek_smoke_streaming
        test_deepseek_multiTurn_nonStreaming
        test_deepseek_multiTurn_streaming
        test_deepseek_toolCall_nonStreaming
        test_deepseek_toolCall_streaming
        test_deepseek_refusal_nonStreaming
        test_deepseek_refusal_streaming
        test_deepseek_thinking_toolCall_nonStreaming
        test_deepseek_thinking_toolCall_streaming
        test_deepseek_thinking_smoke_captures_reasoning
        test_deepseek_thinking_assistantTurn_roundTrips
        test_deepseek_thinking_userToggle_propagates
        test_deepseek_thinking_nonStreaming_deliversReasoningToDelegate
        test_deepseek_thinking_nonStreaming_plainText_aiConversation_multiTurn
        test_deepseek_thinking_userToggleOff_emitsDisabled
        test_deepseek_thinking_reasoningOnlyAssistant_roundTrips
        test_openai_refusal_nonStreaming
        test_openai_refusal_streaming
        test_openai_hostedCodeInterpreter
        test_anthropic_chatReload_paired_nonStreaming
        test_anthropic_chatReload_paired_streaming
        test_anthropic_chatReload_orphan_nonStreaming
        test_anthropic_chatReload_orphan_streaming
        test_gemini_chatReload_paired_nonStreaming
        test_gemini_chatReload_paired_streaming
        test_gemini_chatReload_orphan_nonStreaming
        test_gemini_chatReload_orphan_streaming
        test_openai_chatReload_paired_nonStreaming
        test_openai_chatReload_paired_streaming
        test_openai_chatReload_orphan_nonStreaming
        test_openai_chatReload_orphan_streaming
        test_openai_chatCompletions_chatReload_paired_nonStreaming
        test_openai_chatCompletions_chatReload_paired_streaming
        test_openai_chatCompletions_chatReload_orphan_nonStreaming
        test_openai_chatCompletions_chatReload_orphan_streaming
        test_deepseek_chatReload_paired_nonStreaming
        test_deepseek_chatReload_paired_streaming
        test_deepseek_chatReload_orphan_nonStreaming
        test_deepseek_chatReload_orphan_streaming
    )
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
