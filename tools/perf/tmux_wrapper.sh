#!/usr/bin/env bash
#
# tmux_wrapper.sh - Tmux session management for perf tests
#
# Provides functions to wrap scripts in auto-cleanup tmux sessions.
# Source this file and call tmux_ensure_wrapped "$@" early in your script.
#
# Usage:
#   source "$(dirname "$0")/tmux_wrapper.sh"
#   tmux_ensure_wrapped "$@"  # Re-execs inside tmux if --tmux specified
#

# Session name for this test run (set when we create a session)
_TMUX_PERF_SESSION=""

# Generate a unique session name
_tmux_session_name() {
  echo "iterm2-perf-$$-$(date +%s)"
}

# Register cleanup trap to kill our tmux session on exit
# Call this after creating/entering a tmux session
tmux_register_cleanup() {
  if [[ -z "$_TMUX_PERF_SESSION" ]]; then
    return
  fi

  _tmux_cleanup() {
    if [[ -n "$_TMUX_PERF_SESSION" ]]; then
      # Kill the session (also kills all windows/panes)
      tmux kill-session -t "$_TMUX_PERF_SESSION" 2>/dev/null || true
    fi
  }

  trap _tmux_cleanup EXIT INT TERM
}

# Check if --tmux is in the argument list
_tmux_option_present() {
  for arg in "$@"; do
    if [[ "$arg" == "--tmux" ]]; then
      return 0
    fi
  done
  return 1
}

# Remove --tmux from argument list (for re-exec)
_tmux_strip_option() {
  local args=()
  for arg in "$@"; do
    if [[ "$arg" != "--tmux" ]]; then
      args+=("$arg")
    fi
  done
  echo "${args[@]}"
}

# Ensure script is running inside a tmux session
# If not in tmux and --tmux was specified, re-exec inside a new session
# If already in tmux, just register cleanup
# If tmux not installed, warn and continue
#
# Usage: tmux_ensure_wrapped "$@"
# Returns: 0 if continuing, exits/re-execs otherwise
tmux_ensure_wrapped() {
  # Check if --tmux option is present
  if ! _tmux_option_present "$@"; then
    return 0  # --tmux not specified, continue normally
  fi

  # Check if tmux is installed
  if ! command -v tmux &>/dev/null; then
    echo "Warning: tmux not installed, running without tmux wrapper" >&2
    return 0
  fi

  # Check if already inside tmux
  if [[ -n "${TMUX:-}" ]]; then
    # Already in tmux - check if this is our managed session
    if [[ -n "${_ITERM2_PERF_TMUX_SESSION:-}" ]]; then
      _TMUX_PERF_SESSION="$_ITERM2_PERF_TMUX_SESSION"
      tmux_register_cleanup
    fi
    return 0
  fi

  # Not in tmux - create a new session and re-exec
  _TMUX_PERF_SESSION="$(_tmux_session_name)"
  export _ITERM2_PERF_TMUX_SESSION="$_TMUX_PERF_SESSION"

  # Get the original script path
  local script_path="${BASH_SOURCE[1]}"
  if [[ ! -f "$script_path" ]]; then
    script_path="$0"
  fi

  # Build args without --tmux (we're now inside tmux, don't need it)
  local stripped_args
  stripped_args=$(_tmux_strip_option "$@")

  echo "Creating tmux session: $_TMUX_PERF_SESSION"

  # Create session and run the script inside it
  # Ensure session terminates when command completes
  tmux new-session -s "$_TMUX_PERF_SESSION" -d "bash -c '$script_path $stripped_args; exit 0'"
  tmux set-option -t "$_TMUX_PERF_SESSION" remain-on-exit off

  # If we have a TTY, attach interactively; otherwise wait for completion
  if [[ -t 0 ]]; then
    echo "Attaching to tmux session..."
    exec tmux attach -t "$_TMUX_PERF_SESSION"
  else
    echo "No TTY - waiting for tmux session to complete..."
    # Wait for the session to finish
    while tmux has-session -t "$_TMUX_PERF_SESSION" 2>/dev/null; do
      sleep 1
    done
    echo "Tmux session completed."
    exit 0
  fi
}

# Get current session name (if any)
tmux_session_name() {
  echo "$_TMUX_PERF_SESSION"
}

# Check if we're running inside a tmux session we manage
tmux_is_wrapped() {
  [[ -n "$_TMUX_PERF_SESSION" ]]
}
