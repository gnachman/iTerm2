#!/usr/bin/env bash
set -euo pipefail

# Check that no iTerm2 instance is already running
if pgrep -x iTerm2 >/dev/null 2>&1; then
  echo "Error: iTerm2 is already running. Please close all iTerm2 instances." >&2
  exit 1
fi

# Get script directory early (needed for relative paths)
script_dir_early="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'USAGE'
Usage: run_multi_tab_stress_test.sh [OPTIONS] /path/to/iTerm2.app

Opens iTerm2, starts a single profiler, creates N tabs running a stress load
for the specified duration (default 20 seconds), waits for completion, then
analyzes the profile output.

Options:
  --synchronized-start=BOOL
                 Synchronize tab startup: all tabs signal ready, then start
                 generating load simultaneously. This separates tab creation
                 overhead from the actual stress test.
                 Values: true/false, yes/no, 1/0 (default: true)

  --inject       Enable continuous interaction injection during stress test.
                 Exercises latency instrumentation with periodic events:
                   - Keyboard input every 500ms (single character)
                   - Scroll events every 2s (Page Up/Down alternating)
                   - Tab switches every 3s (cycles through all tabs)
                 Requires synchronized start (the default).

  --dtrace       Enable enhanced DTrace UX metrics collection. Measures:
                   - Update cadence (UI refresh rate from cadence controller)
                   - Adaptive frame rate mode (60fps/30fps/1fps)
                   - Lock contention (joined thread time)
                 Requires root privileges.

  --mode=MODE    Stress test mode. Available modes:

                 Terminal output stress (stress_load.py):
                   normal     - mixed output patterns, no screen clears (default)
                   buffer     - long lines (~600 chars), stresses line buffers
                   clearcodes - all patterns including clear/erase sequences
                   flood      - maximum throughput using 'yes' (no throttling)
                   all        - runs normal, buffer, clearcodes in sequence

                 Dashboard/UI stress (load_dashboard.py):
                   htop       - CPU meters + scrolling process list
                   watch      - full-screen clear + redraw every 100ms
                   progress   - 20 progress bars updating in place
                   table      - fixed header + scroll region body
                   status     - grid of color-coded service status cells

  --title[=MS]   Inject OSC 0 title changes every MS milliseconds (default 2000ms).
                 Exercises TitleUpdate and TabTitleUpdate latency instrumentation.

  --tabs=COUNTS  Comma-separated list of tab counts to test sequentially (1-24).
                 Example: --tabs=1,3,5,10
                 Runs a separate test for each count and shows a summary table.
                 If not specified, defaults to 10 tabs.

  -t, --time=SEC Duration in seconds (default: 20).

  --fps=N        Target frame rate for dashboard modes (default: 30).
                 Use 0 for unthrottled (as fast as possible).
                 Ignored for stress modes (normal, buffer, clearcodes, flood).

  --speed=SPEED  Output speed: normal (default) or slow.
                 slow: adds 100ms delay after each output iteration.

  --forever      Run stress loads indefinitely without profiling or data
                 collection. Useful for manual testing or external profiling.
                 Press Ctrl-C to stop. Ignores duration parameter.

  --tmux         Run stress_load.py inside tmux sessions within iTerm2 tabs.
                 Each tab gets its own tmux session with a unique name.
                 Sessions auto-close when the stress load completes.
                 Cleanup is attempted on Ctrl-C or script exit.

  --load-script=PATH
                 Use a custom load generator script instead of the built-in ones.
                 The script must accept: duration label --sync-dir DIR [--mode=X]

  --suite=NAME   Use a custom UserDefaults suite for isolated preferences.
                 Default: com.iterm2.defaults (reproducible test environment)
                 Use --suite=user to use your normal preferences (com.googlecode.iterm2)
                 Use --suite=none to explicitly disable suite isolation
                 Example: --suite=com.mytest creates fresh preferences
                 Note: Passed to iTerm2 as "-suite NAME" (single dash, space-separated)

  --video[=DIR]  Record the screen during each test iteration.
                 Videos are saved as MOV files with timestamps.
                 Optional DIR specifies output directory (default: /tmp).
                 Uses macOS screencapture; screen recording permission required.

  --self-time    Run self-time profiling using DTrace profile provider.
                 Shows which functions actually burn CPU (not just call count).
                 Requires sudo. Output is analyzed to filter non-actionable symbols.
                 Results show iTerm2 code hotspots for optimization.

USAGE
}

# Parse arguments
synchronized_start=true  # Default to synchronized (better for profiling)
inject_mode=false
dtrace_mode=false
self_time_mode=false  # self-time profiling with profile provider
forever_mode=false
tmux_mode=false
title_arg=""  # empty = disabled, value = milliseconds
stress_mode=""
tabs_arg=""
speed_arg="normal"
fps_arg=""  # empty = use default 30fps
load_script_arg=""  # empty = use default stress_load.py
duration_arg=""  # empty = use default 20s
suite_name="com.iterm2.defaults"  # default suite for reproducible tests
video_mode=false
video_output_dir="/tmp"  # default video output directory
positional_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --synchronized-start=*)
      val="${1#--synchronized-start=}"
      val_lower=$(echo "$val" | tr '[:upper:]' '[:lower:]')
      case "$val_lower" in
        false|no|0) synchronized_start=false ;;
        true|yes|1) synchronized_start=true ;;
        *) echo "Error: --synchronized-start requires true/false/yes/no/1/0, got '$val'" >&2; exit 1 ;;
      esac
      shift
      ;;
    --inject)
      inject_mode=true
      shift
      ;;
    --dtrace)
      dtrace_mode=true
      shift
      ;;
    --forever)
      forever_mode=true
      shift
      ;;
    --tmux)
      tmux_mode=true
      shift
      ;;
    --load-script=*)
      load_script_arg="${1#--load-script=}"
      shift
      ;;
    --suite=*)
      suite_val="${1#--suite=}"
      case "$suite_val" in
        user) suite_name="com.googlecode.iterm2" ;;  # Use normal iTerm2 prefs
        none|"") suite_name="" ;;  # No suite isolation
        *) suite_name="$suite_val" ;;  # Custom suite name
      esac
      shift
      ;;
    --video)
      video_mode=true
      shift
      ;;
    --video=*)
      video_mode=true
      video_output_dir="${1#--video=}"
      shift
      ;;
    --self-time)
      self_time_mode=true
      shift
      ;;
    --title)
      title_arg="2000"  # default 2000ms
      shift
      ;;
    --title=*)
      title_arg="${1#--title=}"
      if ! [[ "$title_arg" =~ ^[0-9]+$ ]]; then
        echo "Error: --title requires a numeric millisecond value, got '$title_arg'" >&2
        exit 1
      fi
      shift
      ;;
    --mode=*)
      stress_mode="$1"
      shift
      ;;
    --tabs=*)
      tabs_arg="${1#--tabs=}"
      shift
      ;;
    --speed=*)
      speed_arg="${1#--speed=}"
      if [[ "$speed_arg" != "normal" && "$speed_arg" != "slow" ]]; then
        echo "Error: --speed requires 'normal' or 'slow', got '$speed_arg'" >&2
        exit 1
      fi
      shift
      ;;
    --fps=*)
      fps_arg="${1#--fps=}"
      if ! [[ "$fps_arg" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        echo "Error: --fps must be a non-negative number, got '$fps_arg'" >&2
        exit 1
      fi
      shift
      ;;
    --time=*)
      duration_arg="${1#--time=}"
      shift
      ;;
    -t)
      if [[ $# -lt 2 ]]; then
        echo "Error: -t requires a value" >&2
        exit 1
      fi
      duration_arg="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      positional_args+=("$1")
      shift
      ;;
  esac
done

set -- "${positional_args[@]}"

# Note: --tmux mode wraps stress_load.py in tmux sessions inside iTerm2 tabs,
# not the test harness itself.

# Valid modes (all handled by stress_load.py)
valid_modes="normal buffer clearcodes flood htop watch progress table status all"

# Validate mode(s) if specified
if [[ -n "$stress_mode" ]]; then
  mode_value="${stress_mode#--mode=}"
  IFS=',' read -ra mode_list <<< "$mode_value"
  for m in "${mode_list[@]}"; do
    if [[ ! " $valid_modes " =~ " $m " ]]; then
      echo "Error: Unknown mode '$m'" >&2
      echo "  Valid modes: $valid_modes" >&2
      exit 1
    fi
  done
fi

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

app_path="$1"

# Display suite configuration
if [[ -n "$suite_name" ]]; then
  if [[ "$suite_name" == "com.iterm2.defaults" ]]; then
    echo "Using test suite: $suite_name (isolated preferences for reproducible tests)"
  elif [[ "$suite_name" == "com.googlecode.iterm2" ]]; then
    echo "Using user's normal preferences (--suite=user)"
  else
    echo "Using custom suite: $suite_name"
  fi
else
  echo "Using user's normal preferences (no suite isolation)"
fi

# Duration: prefer --time/-t, then positional arg, then default
if [[ -n "$duration_arg" ]]; then
  duration="$duration_arg"
elif [[ $# -ge 2 ]]; then
  duration="$2"
else
  duration=20
fi

# Parse tab counts
tab_counts=()
if [[ -n "$tabs_arg" ]]; then
  IFS=',' read -ra tab_counts <<< "$tabs_arg"
  for tc in "${tab_counts[@]}"; do
    if ! [[ "$tc" =~ ^[0-9]+$ ]] || [[ "$tc" -lt 1 ]] || [[ "$tc" -gt 24 ]]; then
      echo "Error: tab count must be an integer between 1 and 24, got '$tc'" >&2
      exit 1
    fi
  done
else
  tab_counts=(10)  # Default to 10 tabs
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Determine load script: explicit --load-script or default stress_load.py
if [[ -n "$load_script_arg" ]]; then
  if [[ "$load_script_arg" == /* ]]; then
    load_script="$load_script_arg"
  else
    load_script="$script_dir/$load_script_arg"
  fi
else
  load_script="$script_dir/stress_load.py"
fi
analyze_script="$script_dir/analyze_profile.py"

if [[ ! -d "$app_path" ]]; then
  echo "Error: iTerm2 app not found at '$app_path'" >&2
  exit 1
fi

# Extract build metadata from app's Info.plist
app_plist="$app_path/Contents/Info.plist"
if [[ -f "$app_plist" ]]; then
  app_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app_plist" 2>/dev/null || echo "unknown")
  build_commit=$(/usr/libexec/PlistBuddy -c "Print :BuildCommit" "$app_plist" 2>/dev/null || echo "")
  build_branch=$(/usr/libexec/PlistBuddy -c "Print :BuildBranch" "$app_plist" 2>/dev/null || echo "")
  build_date=$(/usr/libexec/PlistBuddy -c "Print :BuildDate" "$app_plist" 2>/dev/null || echo "")
  build_uncommitted=$(/usr/libexec/PlistBuddy -c "Print :BuildUncommittedChanges" "$app_plist" 2>/dev/null || echo "")
else
  echo "Warning: Could not read Info.plist from app bundle" >&2
  app_version="unknown"
  build_commit=""
  build_branch=""
  build_date=""
  build_uncommitted=""
fi

if ! [[ "$duration" =~ ^[0-9]+$ ]] || [[ "$duration" -lt 1 ]]; then
  echo "Error: duration must be a positive integer" >&2
  exit 1
fi

if [[ ! -f "$load_script" ]]; then
  echo "Error: stress load script not found at '$load_script'" >&2
  exit 1
fi

if [[ ! -f "$analyze_script" ]]; then
  echo "Error: analyze script not found at '$analyze_script'" >&2
  exit 1
fi

# Video mode validation
if [[ "$video_mode" == true ]]; then
  # Check for GetWindowID tool
  if ! command -v GetWindowID &>/dev/null; then
    echo "Error: --video requires GetWindowID (brew install smokris/getwindowid/getwindowid)" >&2
    exit 1
  fi
  # Validate output directory
  video_output_dir="${video_output_dir/#\~/$HOME}"
  if [[ ! -d "$video_output_dir" ]]; then
    echo "Error: Video output directory does not exist: $video_output_dir" >&2
    exit 1
  fi
  echo "Video recording enabled (output: $video_output_dir)"
fi

# DTrace requires root
if [[ "$dtrace_mode" == true ]]; then
  dtrace_script="$script_dir/iterm_ux_metrics_v2.d"
  if [[ ! -f "$dtrace_script" ]]; then
    echo "Error: DTrace script not found at '$dtrace_script'" >&2
    exit 1
  fi
  echo "DTrace mode enabled (using $dtrace_script)"
  if [[ $EUID -ne 0 ]]; then
    echo "Warning: DTrace requires root. If dtrace fails, re-run as:" >&2
    echo "  sudo $0 $*" >&2
    echo "Note: Running scripts as root is generally not recommended." >&2
    echo "      Review the script contents before running with elevated privileges." >&2
  fi
fi

# Global arrays to collect results across runs
declare -a RESULT_TAB_COUNTS=()
declare -a RESULT_ITERATION_RATES=()
declare -a RESULT_TOTAL_ITERATIONS=()
# DTrace UX metrics (only populated when --dtrace is used)
declare -a RESULT_CONTENT_FRAMES=()
declare -a RESULT_REFRESHES=()
declare -a RESULT_METAL_FRAMES=()
declare -a RESULT_CONTENT_FPS=()
declare -a RESULT_REFRESH_FPS=()
declare -a RESULT_METAL_FPS=()
declare -a RESULT_JOIN_CALLS=()
declare -a RESULT_JOIN_TIME_US=()
declare -a RESULT_ADAPTIVE_MODE=()
# Latency metrics (from mtperf_latency_*.txt)
declare -a RESULT_KEYDOWN_MEAN_MS=()
declare -a RESULT_KEYDOWN_MAX_MS=()
declare -a RESULT_TITLE_MEAN_MS=()
declare -a RESULT_TITLE_MAX_MS=()
declare -a RESULT_GCD_TIMER_CREATE=()
declare -a RESULT_GCD_TIMER_FIRE=()
declare -a RESULT_GCD_FIRE_RATIO=()
declare -a RESULT_NS_TIMER_CREATE=()
declare -a RESULT_NS_TIMER_FIRE=()
declare -a RESULT_NS_FIRE_RATIO=()
declare -a RESULT_CADENCE_MISMATCH_PCT=()
# Derived metrics
declare -a RESULT_ITERS_PER_FRAME=()

# Create AppleScript file once (reused across runs)
applescript_file=$(mktemp)
cat > "$applescript_file" <<'APPLESCRIPT'
on run argv
  set tabCount to (item 1 of argv) as integer
  set scriptPath to item 2 of argv
  set duration to item 3 of argv
  set syncDir to item 4 of argv
  set stressMode to item 5 of argv
  set titleArg to item 6 of argv
  set speedArg to item 7 of argv
  set fpsArg to item 8 of argv
  set tmuxPrefix to item 9 of argv

  tell application "iTerm2"
      activate
      -- Use the existing window (opened by app launch) instead of creating a new one
      set theWindow to current window

      -- Set consistent window size and position for reproducible tests
      set bounds of theWindow to {864, 34, 1728, 1117}

      set sessionList to {}

      repeat with i from 1 to tabCount
        if i is not 1 then
          tell theWindow to create tab with default profile
        end if
        delay 1
        set theSession to current session of theWindow
        set innerCmd to "python3 " & quoted form of scriptPath & " " & duration & " tab_" & i
        if syncDir is not "" then
          set innerCmd to innerCmd & " --sync-dir " & quoted form of syncDir
        end if
        if stressMode is not "" then
          set innerCmd to innerCmd & " " & stressMode
        end if
        if titleArg is not "" then
          set innerCmd to innerCmd & " --title=" & titleArg
        end if
        if speedArg is not "" and speedArg is not "normal" then
          set innerCmd to innerCmd & " --speed=" & speedArg
        end if
        if fpsArg is not "" then
          set innerCmd to innerCmd & " --fps=" & fpsArg
        end if
        -- Wrap in tmux if prefix provided, otherwise run directly
        if tmuxPrefix is not "" then
          set sessionName to tmuxPrefix & "-tab" & i
          set cmd to "tmux new-session -s " & quoted form of sessionName & " '" & innerCmd & "; exit'"
        else
          set cmd to innerCmd & "; exit"
        end if
        tell theSession to write text cmd
        set end of sessionList to theSession
      end repeat

      -- Wait for initial startup
      delay 5

      -- Poll until all sessions complete
      repeat
        set doneCount to 0
        repeat with s in sessionList
          try
            if is at shell prompt of s then
              set doneCount to doneCount + 1
            end if
          on error
            set doneCount to doneCount + 1
          end try
        end repeat
        if doneCount = tabCount then exit repeat
        delay 1
      end repeat

      -- Don't close window here; let main script handle shutdown order
      -- (needed so dtrace can be signaled before iTerm2 exits)
  end tell
end run
APPLESCRIPT

# Create AppleScript for forever mode (no polling, no close)
applescript_forever_file=$(mktemp)
cat > "$applescript_forever_file" <<'APPLESCRIPT'
on run argv
  set tabCount to (item 1 of argv) as integer
  set scriptPath to item 2 of argv
  set stressMode to item 3 of argv
  set titleArg to item 4 of argv
  set speedArg to item 5 of argv
  set fpsArg to item 6 of argv
  set tmuxPrefix to item 7 of argv

  tell application "iTerm2"
      activate
      set theWindow to current window

      -- Set consistent window size and position for reproducible tests
      set bounds of theWindow to {864, 34, 1728, 1117}

      repeat with i from 1 to tabCount
        if i is not 1 then
          tell theWindow to create tab with default profile
        end if
        delay 1
        set theSession to current session of theWindow
        -- Run forever (no duration limit)
        set innerCmd to "python3 " & quoted form of scriptPath & " 999999999 tab_" & i
        if stressMode is not "" then
          set innerCmd to innerCmd & " " & stressMode
        end if
        if titleArg is not "" then
          set innerCmd to innerCmd & " --title=" & titleArg
        end if
        if speedArg is not "" and speedArg is not "normal" then
          set innerCmd to innerCmd & " --speed=" & speedArg
        end if
        if fpsArg is not "" then
          set innerCmd to innerCmd & " --fps=" & fpsArg
        end if
        -- Wrap in tmux if prefix provided, otherwise run directly
        if tmuxPrefix is not "" then
          set sessionName to tmuxPrefix & "-tab" & i
          set cmd to "tmux new-session -s " & quoted form of sessionName & " '" & innerCmd & "; exit'"
        else
          set cmd to innerCmd
        end if
        tell theSession to write text cmd
      end repeat
  end tell
end run
APPLESCRIPT

# Get power source from pmset
get_power_source() {
  pmset -g batt 2>/dev/null | head -1 | sed "s/.*Now drawing from '//;s/'.*//g" || echo "Unknown"
}

# Get power/energy mode from pmset (based on current power source)
get_energy_mode() {
  local power_source=$(get_power_source)
  local section=""

  # Determine which section to read from pmset -g custom
  case "$power_source" in
    "AC Power") section="AC Power:" ;;
    "Battery Power") section="Battery Power:" ;;
    "UPS Power") section="UPS Power:" ;;
    *) echo "Unknown"; return ;;
  esac

  # Get powermode for the current power source
  local powermode=$(pmset -g custom 2>/dev/null | awk -v sect="$section" '
    $0 ~ sect { in_section=1; next }
    in_section && /^[A-Z]/ { in_section=0 }
    in_section && /powermode/ { print $NF; exit }
  ')

  case "$powermode" in
    0) echo "Automatic" ;;
    1) echo "Low Power" ;;
    2) echo "High Power/High Performance" ;;
    *) echo "Unknown" ;;
  esac
}

# Cleanup function
# Track tmux session prefix for cleanup (set per-run when --tmux is used)
tmux_session_prefix=""
tmux_tab_count=0

cleanup() {
  # Clean up tmux sessions if we created any
  if [[ -n "$tmux_session_prefix" && "$tmux_tab_count" -gt 0 ]]; then
    for i in $(seq 1 "$tmux_tab_count"); do
      tmux kill-session -t "${tmux_session_prefix}-tab${i}" 2>/dev/null || true
    done
  fi
  # Clean up temp files
  if [[ -n "${sync_dir:-}" && -d "${sync_dir:-}" ]]; then
    rm -rf "$sync_dir"
  fi
  if [[ -n "${applescript_file:-}" && -f "${applescript_file:-}" ]]; then
    rm -f "$applescript_file"
  fi
  if [[ -n "${applescript_forever_file:-}" && -f "${applescript_forever_file:-}" ]]; then
    rm -f "$applescript_forever_file"
  fi
  # Try to quit iTerm2 if it's running (best effort)
  osascript -e 'tell application "iTerm2" to quit' 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Function to run a single test with given tab count
# Results are stored in global RESULT_* arrays
run_single_test() {
  local tab_count=$1
  local run_index=$2

  echo ""
  echo "Run $((run_index + 1)): $tab_count tab(s), ${duration}s duration"

  # Set up sync directory if in sync mode
  # Use /tmp so it's accessible to all users (needed when running as root for dtrace)
  local sync_dir=""
  if [[ "$synchronized_start" == true ]]; then
    sync_dir=$(mktemp -d /tmp/iterm2-perf-sync.XXXXXX)
    chmod 777 "$sync_dir"
    echo "Synchronized start enabled (sync dir: $sync_dir)"
  fi

  # Open iTerm2 and wait for it to launch
  local run_start_epoch
  run_start_epoch=$(date +%s)

  # Launch iTerm2 with suite isolation
  if [[ -n "$suite_name" ]]; then
    open -a "$app_path" --args -suite "$suite_name"
  else
    open -a "$app_path"
  fi
  sleep 2

  # Find iTerm2 PID
  local iterm_pid=""
  for _ in {1..10}; do
    iterm_pid=$(pgrep -x iTerm2 || true)
    if [[ -n "$iterm_pid" ]]; then
      break
    fi
    sleep 0.5
  done

  if [[ -z "$iterm_pid" ]]; then
    echo "Error: Could not find iTerm2 process" >&2
    [[ -n "$sync_dir" && -d "$sync_dir" ]] && rm -rf "$sync_dir"
    return 1
  fi

  echo "Found iTerm2 PID: $iterm_pid"

  # Size and position window consistently (needed before video capture)
  osascript -e 'tell application "iTerm2" to set bounds of current window to {864, 34, 1728, 1117}'

  # Set up profile output file
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local profile_output="/tmp/iterm2_multi_tab_profile_${timestamp}.txt"
  local dtrace_output="/tmp/iterm2_dtrace_${timestamp}.txt"
  local self_time_output="/tmp/iterm2_self_time_${timestamp}.txt"

  # Start video recording if enabled
  local video_pid=""
  local video_file=""
  if [[ "$video_mode" == true ]]; then
    video_file="${video_output_dir}/iterm2_perf_${tab_count}tabs_${timestamp}.mov"
    local video_duration=$((duration + 10))  # Add buffer for startup/shutdown
    # Get window ID (first non-empty title - safe since we ensure single instance)
    local window_id
    window_id=$(GetWindowID iTerm2 --list | grep -v '^""' | head -1 | sed 's/.*id=//')
    if [[ -z "$window_id" ]]; then
      echo "Warning: Could not get iTerm2 window ID, skipping video recording"
    else
      echo "Starting video recording (window $window_id): $video_file"
      screencapture -v -V "$video_duration" -l"$window_id" "$video_file" &
      video_pid=$!
      sleep 1  # Give screencapture time to initialize
    fi
  fi

  # Calculate profiler duration (load duration + buffer)
  local profiler_duration=$((duration + 5))

  # In sync mode, we start profiler AFTER tabs are ready (to exclude tab creation overhead)
  # In non-sync mode, we start profiler before launching tabs
  local profiler_pid=""
  local dtrace_pid=""
  local self_time_pid=""
  if [[ "$synchronized_start" != true ]]; then
    echo "Starting profiler for ${profiler_duration} seconds..."
    sample "$iterm_pid" "$profiler_duration" -f "$profile_output" &>/dev/null &
    profiler_pid=$!
    # Start DTrace if enabled (with timeout matching profiler duration)
    if [[ "$dtrace_mode" == true ]]; then
      timeout "$((profiler_duration + 30))" dtrace -Z -p "$iterm_pid" -s "$dtrace_script" $profiler_duration > "$dtrace_output" 2>&1 &
      dtrace_pid=$!
      # Wait for dtrace to attach (it prints "Tracing" when ready)
      echo "Waiting for DTrace to attach..."
      for _ in {1..50}; do
        if grep -q "Tracing" "$dtrace_output" 2>/dev/null; then
          echo "DTrace attached."
          break
        fi
        sleep 0.2
      done
      if ! grep -q "Tracing" "$dtrace_output" 2>/dev/null; then
        echo "Warning: DTrace may not have attached properly"
      fi
    else
      sleep 1
    fi
    # Start self-time profiling if enabled
    if [[ "$self_time_mode" == true ]]; then
      local self_time_script="$script_dir/iterm_self_time.d"
      echo "Starting self-time profiler for ${profiler_duration} seconds..."
      timeout "$((profiler_duration + 30))" dtrace -Z -p "$iterm_pid" -s "$self_time_script" $profiler_duration > "$self_time_output" 2>&1 &
      self_time_pid=$!
      sleep 1  # Give dtrace time to attach
    fi
  fi

  echo "Launching $tab_count tabs, each running stress test for $duration seconds..."

  # Generate unique tmux session prefix if --tmux mode
  local tmux_prefix=""
  if [[ "$tmux_mode" == true ]]; then
    tmux_prefix="iterm2-perf-$$-$(date +%s)"
    tmux_session_prefix="$tmux_prefix"  # Store globally for cleanup
    tmux_tab_count="$tab_count"
  fi

  # Launch tabs with load script (in background so we can coordinate sync)
  osascript "$applescript_file" "$tab_count" "$load_script" "$duration" "${sync_dir:-}" "$stress_mode" "$title_arg" "$speed_arg" "$fps_arg" "$tmux_prefix" &
  local applescript_pid=$!

  # If sync mode, wait for all ready signals, start profiler, then send go signal
  if [[ "$synchronized_start" == true ]]; then
    echo "Waiting for all tabs to signal ready..."

    # Wait for all ready files
    local ready_count=0
    while [[ $ready_count -lt $tab_count ]]; do
      ready_count=$(find "$sync_dir" -name "ready_tab_*" 2>/dev/null | wc -l | tr -d ' ')
      if [[ $ready_count -lt $tab_count ]]; then
        sleep 0.2
      fi
    done

    echo "All $tab_count tabs ready."

    # Start profiler NOW (after tab creation, before load generation)
    echo "Starting profiler for ${profiler_duration} seconds..."
    sample "$iterm_pid" "$profiler_duration" -f "$profile_output" &>/dev/null &
    profiler_pid=$!
    # Start DTrace if enabled (with timeout matching profiler duration)
    if [[ "$dtrace_mode" == true ]]; then
      timeout "$((profiler_duration + 30))" dtrace -Z -p "$iterm_pid" -s "$dtrace_script" $profiler_duration > "$dtrace_output" 2>&1 &
      dtrace_pid=$!
      # Wait for dtrace to attach (it prints "Tracing" when ready)
      echo "Waiting for DTrace to attach..."
      for _ in {1..50}; do
        if grep -q "Tracing" "$dtrace_output" 2>/dev/null; then
          echo "DTrace attached."
          break
        fi
        sleep 0.2
      done
      if ! grep -q "Tracing" "$dtrace_output" 2>/dev/null; then
        echo "Warning: DTrace may not have attached properly"
      fi
    else
      sleep 1  # Brief pause for profiler to attach
    fi
    # Start self-time profiling if enabled
    if [[ "$self_time_mode" == true ]]; then
      local self_time_script="$script_dir/iterm_self_time.d"
      echo "Starting self-time profiler for ${profiler_duration} seconds..."
      timeout "$((profiler_duration + 30))" dtrace -Z -p "$iterm_pid" -s "$self_time_script" $profiler_duration > "$self_time_output" 2>&1 &
      self_time_pid=$!
      sleep 1  # Give dtrace time to attach
    fi

    echo "Sending go signal..."
    touch "$sync_dir/go"

    # Start interaction injection if enabled (runs in background)
    if [[ "$inject_mode" == true ]]; then
      echo "Starting interaction injection (keyboard, scroll, tab switch)..."
      (
        sleep 2  # Let stress_load.py get going

        # Timing configuration (in 100ms ticks)
        local tick=0
        local keyboard_ticks=5    # every 500ms - keyboard input
        local scroll_ticks=20     # every 2s - scroll events
        local tab_ticks=30        # every 3s - tab switches
        local current_tab=1
        local scroll_direction=1  # 1 = down, -1 = up

        # Calculate end time (stop 2s before test ends)
        local inject_end=$((SECONDS + duration - 2))

        # Counters for summary
        local keyboard_count=0
        local scroll_count=0
        local tab_switch_count=0

        while [[ $SECONDS -lt $inject_end ]]; do
          tick=$((tick + 1))

          # Periodic keyboard input (every 500ms)
          # Send a single character to exercise keyboard input latency path
          if (( tick % keyboard_ticks == 0 )); then
            osascript -e 'tell application "iTerm2" to tell current session of current window to write text "."' 2>/dev/null || true
            keyboard_count=$((keyboard_count + 1))
          fi

          # Periodic scroll events (every 2s)
          # Alternate between Page Down and Page Up to stay in view
          if (( tick % scroll_ticks == 0 )); then
            if (( scroll_direction == 1 )); then
              # Page Down (key code 121)
              osascript -e 'tell application "System Events" to tell process "iTerm2" to key code 121' 2>/dev/null || true
            else
              # Page Up (key code 116)
              osascript -e 'tell application "System Events" to tell process "iTerm2" to key code 116' 2>/dev/null || true
            fi
            scroll_direction=$((scroll_direction * -1))
            scroll_count=$((scroll_count + 1))
          fi

          # Periodic tab switches (every 3s)
          if (( tick % tab_ticks == 0 )); then
            current_tab=$(( (current_tab % tab_count) + 1 ))
            osascript -e "tell application \"iTerm2\" to tell current window to select tab $current_tab" 2>/dev/null || true
            tab_switch_count=$((tab_switch_count + 1))
          fi

          sleep 0.1
        done

        echo "Injection complete: keyboard=$keyboard_count scroll=$scroll_count tabs=$tab_switch_count"
      ) &
      local inject_pid=$!
    fi
  fi

  # Wait for AppleScript to complete
  wait "$applescript_pid" || true

  # Wait for injection to complete if it was started
  if [[ "$inject_mode" == true && -n "${inject_pid:-}" ]]; then
    wait "$inject_pid" 2>/dev/null || true
  fi

  echo "All tabs completed. Waiting for profiler..."
  if [[ -n "$profiler_pid" ]]; then
    wait "$profiler_pid" 2>/dev/null || true
  fi

  # Signal DTrace to output its END block summary before quitting iTerm2
  # (timeout is just a failsafe; we want a clean shutdown here)
  if [[ "$dtrace_mode" == true && -n "$dtrace_pid" ]]; then
    echo "Signaling DTrace to finish..."
    kill -INT "$dtrace_pid" 2>/dev/null || true
    # Give dtrace time to output its END block
    for _ in {1..20}; do
      if ! kill -0 "$dtrace_pid" 2>/dev/null; then
        break
      fi
      sleep 0.2
    done
    wait "$dtrace_pid" 2>/dev/null || true
  fi

  # Aggregate iteration stats from tabs (if sync mode)
  local total_iterations=0
  local iteration_rate=0
  if [[ "$synchronized_start" == true && -d "$sync_dir" ]]; then
    for stats_file in "$sync_dir"/stats_*; do
      if [[ -f "$stats_file" ]]; then
        local iterations
        iterations=$(head -1 "$stats_file")
        total_iterations=$((total_iterations + iterations))
      fi
    done
    iteration_rate=$((total_iterations / duration))
    echo ""
    echo "============================================================"
    echo "Iteration Summary"
    echo "============================================================"
    echo "  Total iterations: $total_iterations"
    echo "  Tabs: $tab_count"
    echo "  Duration: ${duration}s"
    echo "  Rate: $iteration_rate iterations/sec"
    echo "============================================================"

    # Clean up sync dir
    rm -rf "$sync_dir"
  fi

  echo ""
  python3 "$analyze_script" "$profile_output"

  # Stop video recording if it was started
  if [[ -n "$video_pid" ]]; then
    echo "Stopping video recording..."
    kill -INT "$video_pid" 2>/dev/null || true
    wait "$video_pid" 2>/dev/null || true
    if [[ -f "$video_file" ]]; then
      echo "Video saved: $video_file"
    fi
  fi

  # Quit the test iTerm2 instance cleanly via AppleScript (Command-Q)
  echo ""
  echo "Shutting down test iTerm2..."
  osascript -e 'tell application "iTerm2" to quit' 2>/dev/null || true

  # Wait for app to fully terminate (needed for MTPerfWriteToFile to complete)
  for _ in {1..30}; do
    if ! pgrep -f "$app_path" >/dev/null 2>&1; then
      break
    fi
    sleep 0.2
  done

  # Parse and display DTrace UX metrics (only if --dtrace was specified)
  local content_frames="0" refreshes="0" metal_frames="0"
  local content_fps="0" refresh_fps="0" metal_fps="0"
  local join_calls="0" join_time_ns="0" join_time_us="0"
  local adaptive_mode="-"
  local dtrace_duration="$duration"

  if [[ "$dtrace_mode" == true && -f "$dtrace_output" ]]; then
    # Parse DTrace UX metrics output
    dtrace_duration=$(awk '/duration:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' "$dtrace_output")
    [[ -z "$dtrace_duration" || "$dtrace_duration" == "0" ]] && dtrace_duration="$duration"

    # Parse frame counts
    content_frames=$(awk '/Content frames.*setNeedsDisplay/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' "$dtrace_output")
    refreshes=$(awk '/Total refreshes.*cadence/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' "$dtrace_output")
    metal_frames=$(awk '/Metal frames.*GPU/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' "$dtrace_output")

    # Parse rates (from RATES section)
    content_fps=$(awk '/Content frames\/sec:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' "$dtrace_output")
    refresh_fps=$(awk '/Refreshes\/sec:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' "$dtrace_output")
    metal_fps=$(awk '/Metal frames\/sec:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' "$dtrace_output")

    # Parse join contention
    join_calls=$(awk '/Light join calls:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' "$dtrace_output")
    join_time_ns=$(awk '/Light join time:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' "$dtrace_output")

    # Parse adaptive mode (count which mode was used most)
    local mode_60fps=$(awk '/60fps mode calls:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' "$dtrace_output")
    local mode_30fps=$(awk '/30fps mode calls:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' "$dtrace_output")
    local mode_1fps=$(awk '/1fps mode calls:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' "$dtrace_output")

    # Parse FairnessScheduler metrics (0 = legacy path)
    local fairness_register=$(awk '/Register calls:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' "$dtrace_output")
    local fairness_enqueue=$(awk '/SessionDidEnqueueWork:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' "$dtrace_output")
    local fairness_execute=$(awk '/ExecuteTurn calls:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' "$dtrace_output")

    [[ -z "$content_frames" ]] && content_frames="0"
    [[ -z "$refreshes" ]] && refreshes="0"
    [[ -z "$metal_frames" ]] && metal_frames="0"
    [[ -z "$content_fps" ]] && content_fps="0"
    [[ -z "$refresh_fps" ]] && refresh_fps="0"
    [[ -z "$metal_fps" ]] && metal_fps="0"
    [[ -z "$join_calls" ]] && join_calls="0"
    [[ -z "$join_time_ns" ]] && join_time_ns="0"
    [[ -z "$mode_60fps" ]] && mode_60fps="0"
    [[ -z "$mode_30fps" ]] && mode_30fps="0"
    [[ -z "$mode_1fps" ]] && mode_1fps="0"
    [[ -z "$fairness_register" ]] && fairness_register="0"
    [[ -z "$fairness_enqueue" ]] && fairness_enqueue="0"
    [[ -z "$fairness_execute" ]] && fairness_execute="0"

    # Convert join time to microseconds
    if [[ "$join_time_ns" -gt 0 ]]; then
      join_time_us=$((join_time_ns / 1000))
    fi

    # Determine dominant adaptive mode
    if [[ "$mode_30fps" -gt "$mode_60fps" && "$mode_30fps" -gt "$mode_1fps" ]]; then
      adaptive_mode="30fps"
    elif [[ "$mode_60fps" -gt "$mode_1fps" ]]; then
      adaptive_mode="60fps"
    elif [[ "$mode_1fps" -gt 0 ]]; then
      adaptive_mode="1fps"
    fi

    if [[ "$refreshes" != "0" ]]; then
      echo ""
      echo "============================================================"
      echo "DTrace UX Metrics (duration: ${dtrace_duration}s)"
      echo "============================================================"
      printf "  Adaptive mode:          %s\n" "$adaptive_mode"
      printf "  Content frames:         %s (lines marked dirty)\n" "$content_frames"
      printf "  Refreshes (cadence):    %s\n" "$refreshes"
      printf "  Metal frames (GPU):     %s\n" "$metal_frames"
      echo "  ---"
      printf "  Update cadence:         %s fps (refreshes/sec)\n" "$refresh_fps"
      printf "  Metal frame rate:       %s fps\n" "$metal_fps"
      echo "  ---"
      printf "  Join calls:             %s\n" "$join_calls"
      printf "  Join time:              %s us (total)\n" "$join_time_us"
      echo "  ---"
      if [[ "$fairness_execute" -gt 0 ]]; then
        printf "  FairnessScheduler:      ACTIVE\n"
        printf "    Enqueue calls:        %s\n" "$fairness_enqueue"
        printf "    ExecuteTurn calls:    %s\n" "$fairness_execute"
      else
        printf "  FairnessScheduler:      INACTIVE (legacy path)\n"
      fi
      echo "============================================================"
    fi
  fi

  # Display self-time analysis if enabled
  if [[ "$self_time_mode" == true && -f "$self_time_output" ]]; then
    echo ""
    echo "============================================================"
    echo "Self-Time Analysis (functions that burn CPU directly)"
    echo "============================================================"
    local self_time_analyze_script="$script_dir/analyze_self_time.py"
    if [[ -f "$self_time_analyze_script" ]]; then
      python3 "$self_time_analyze_script" "$self_time_output"
    else
      echo "Warning: analyze_self_time.py not found, showing raw output:"
      cat "$self_time_output"
    fi
    echo ""
    echo "Raw self-time output: $self_time_output"
  fi

  # Store iteration stats in result arrays
  RESULT_TAB_COUNTS+=("$tab_count")
  RESULT_ITERATION_RATES+=("$iteration_rate")
  RESULT_TOTAL_ITERATIONS+=("$total_iterations")

  # Store DTrace metrics in result arrays (if enabled)
  if [[ "$dtrace_mode" == true ]]; then
    RESULT_CONTENT_FRAMES+=("$content_frames")
    RESULT_REFRESHES+=("$refreshes")
    RESULT_METAL_FRAMES+=("$metal_frames")
    RESULT_CONTENT_FPS+=("$content_fps")
    RESULT_REFRESH_FPS+=("$refresh_fps")
    RESULT_METAL_FPS+=("$metal_fps")
    RESULT_JOIN_CALLS+=("$join_calls")
    RESULT_JOIN_TIME_US+=("$join_time_us")
    RESULT_ADAPTIVE_MODE+=("$adaptive_mode")
    # Derived: iterations per metal frame
    if [[ "$metal_frames" -gt 0 ]]; then
      local iters_per_frame
      iters_per_frame=$(awk "BEGIN {printf \"%.1f\", $total_iterations / $metal_frames}")
      RESULT_ITERS_PER_FRAME+=("$iters_per_frame")
    else
      RESULT_ITERS_PER_FRAME+=("-")
    fi
  fi

  # Look for latency instrumentation file (from MTPerfMetrics)
  local latency_file=""
  for _ in {1..30}; do
    latency_file="$(ls -t /tmp/mtperf_latency_*.txt 2>/dev/null | head -1 || true)"
    if [[ -n "$latency_file" && -f "$latency_file" ]]; then
      local latency_mtime
      latency_mtime=$(stat -f "%m" "$latency_file" 2>/dev/null || echo 0)
      if [[ "$latency_mtime" -ge "$run_start_epoch" ]]; then
        break
      fi
    fi
    latency_file=""
    sleep 0.2
  done

  # Parse and display latency metrics
  if [[ -n "$latency_file" && -f "$latency_file" ]]; then
    echo ""
    echo "============================================================"
    echo "Latency Instrumentation"
    echo "============================================================"

    local section="header"  # header, context, latency, counters
    # Parse latency CSV with multiple sections:
    # - Context section: key,value pairs for settings/state
    # - Latency section: metric,count,mean_ns,min_ns,max_ns,stddev_ns
    # - Counters section: metric,count
    while IFS=',' read -r field1 field2 field3 field4 field5 field6; do
      # Track section changes
      case "$field1" in
        "# Context")
          section="context"
          echo "  --- Context ---"
          continue
          ;;
        "# metric")
          section="latency"
          echo ""
          continue
          ;;
        "# Counters")
          section="counters"
          echo ""
          echo "  --- Counters ---"
          continue
          ;;
        \#*)
          # Skip other comment lines
          continue
          ;;
      esac

      case "$section" in
        context)
          # Context format: key,value (2 fields)
          # Display context settings
          printf "  %-40s  %s\n" "$field1" "$field2"
          ;;
        latency)
          # Latency format: metric,count,mean_ns,min_ns,max_ns,stddev_ns (6 fields)
          local metric="$field1" count="$field2" mean_ns="$field3" min_ns="$field4" max_ns="$field5"
          # Skip metrics with zero count
          [[ "$count" == "0" ]] && continue
          # Convert nanoseconds to milliseconds for display
          local mean_ms min_ms max_ms
          mean_ms=$(awk "BEGIN {printf \"%.2f\", $mean_ns / 1000000}")
          min_ms=$(awk "BEGIN {printf \"%.2f\", $min_ns / 1000000}")
          max_ms=$(awk "BEGIN {printf \"%.2f\", $max_ns / 1000000}")
          printf "  %-20s  count: %6s  mean: %8s ms  min: %8s ms  max: %8s ms\n" \
                 "$metric" "$count" "$mean_ms" "$min_ms" "$max_ms"
          ;;
        counters)
          # Counter format: metric,count (2 fields)
          local metric="$field1" count="$field2"
          [[ "$count" == "0" ]] && continue
          printf "  %-24s  %s\n" "$metric" "$count"
          ;;
      esac
    done < "$latency_file"

    # Extract timer metrics for analysis
    local gcd_timer_create gcd_timer_fire ns_timer_create ns_timer_fire
    local cadence_no_change cadence_mismatch
    gcd_timer_create=$(grep "^GCDTimerCreate," "$latency_file" 2>/dev/null | cut -d, -f2 || echo 0)
    gcd_timer_fire=$(grep "^GCDTimerFire," "$latency_file" 2>/dev/null | cut -d, -f2 || echo 0)
    ns_timer_create=$(grep "^NSTimerCreate," "$latency_file" 2>/dev/null | cut -d, -f2 || echo 0)
    ns_timer_fire=$(grep "^NSTimerFire," "$latency_file" 2>/dev/null | cut -d, -f2 || echo 0)
    cadence_no_change=$(grep "^CadenceNoChange," "$latency_file" 2>/dev/null | cut -d, -f2 || echo 0)
    cadence_mismatch=$(grep "^CadenceMismatch," "$latency_file" 2>/dev/null | cut -d, -f2 || echo 0)

    # Show timer efficiency analysis if we have timer data
    local has_timer_data=false
    [[ "$gcd_timer_create" -gt 0 || "$gcd_timer_fire" -gt 0 || "$ns_timer_create" -gt 0 || "$ns_timer_fire" -gt 0 ]] && has_timer_data=true

    if [[ "$has_timer_data" == true ]]; then
      echo ""
      echo "  --- Timer Analysis ---"
      if [[ "$gcd_timer_create" -gt 0 ]]; then
        local gcd_fire_ratio
        gcd_fire_ratio=$(awk "BEGIN {printf \"%.1f\", $gcd_timer_fire / $gcd_timer_create}")
        printf "  GCD fires/create:       %s (create: %s, fire: %s)\n" "$gcd_fire_ratio" "$gcd_timer_create" "$gcd_timer_fire"
      fi
      if [[ "$ns_timer_create" -gt 0 ]]; then
        local ns_fire_ratio
        ns_fire_ratio=$(awk "BEGIN {printf \"%.1f\", $ns_timer_fire / $ns_timer_create}")
        printf "  NSTimer fires/create:   %s (create: %s, fire: %s)\n" "$ns_fire_ratio" "$ns_timer_create" "$ns_timer_fire"
      fi
      if [[ "$cadence_mismatch" -gt 0 || "$cadence_no_change" -gt 0 ]]; then
        local total_checks=$((cadence_mismatch + cadence_no_change))
        local mismatch_pct
        mismatch_pct=$(awk "BEGIN {printf \"%.1f\", 100 * $cadence_mismatch / $total_checks}")
        printf "  Cadence mismatch rate:  %s%% (%s of %s checks)\n" "$mismatch_pct" "$cadence_mismatch" "$total_checks"
      fi
    fi

    echo ""
    echo "  Latency file: $latency_file"
    echo "============================================================"

    # Store latency metrics in result arrays for summary table
    # Extract KeyboardInput latency (mean and max in ms)
    local keydown_line keydown_mean_ns keydown_max_ns keydown_mean_ms keydown_max_ms
    keydown_line=$(grep "^KeyboardInput," "$latency_file" 2>/dev/null || true)
    if [[ -n "$keydown_line" ]]; then
      keydown_mean_ns=$(echo "$keydown_line" | cut -d, -f3)
      keydown_max_ns=$(echo "$keydown_line" | cut -d, -f5)
      keydown_mean_ms=$(awk "BEGIN {printf \"%.2f\", $keydown_mean_ns / 1000000}")
      keydown_max_ms=$(awk "BEGIN {printf \"%.2f\", $keydown_max_ns / 1000000}")
      RESULT_KEYDOWN_MEAN_MS+=("$keydown_mean_ms")
      RESULT_KEYDOWN_MAX_MS+=("$keydown_max_ms")
    else
      RESULT_KEYDOWN_MEAN_MS+=("-")
      RESULT_KEYDOWN_MAX_MS+=("-")
    fi

    # Extract TitleUpdate latency (if --title was used)
    local title_line title_mean_ns title_max_ns title_mean_ms title_max_ms
    title_line=$(grep "^TitleUpdate," "$latency_file" 2>/dev/null || true)
    if [[ -n "$title_line" ]]; then
      title_mean_ns=$(echo "$title_line" | cut -d, -f3)
      title_max_ns=$(echo "$title_line" | cut -d, -f5)
      title_mean_ms=$(awk "BEGIN {printf \"%.2f\", $title_mean_ns / 1000000}")
      title_max_ms=$(awk "BEGIN {printf \"%.2f\", $title_max_ns / 1000000}")
      RESULT_TITLE_MEAN_MS+=("$title_mean_ms")
      RESULT_TITLE_MAX_MS+=("$title_max_ms")
    else
      RESULT_TITLE_MEAN_MS+=("-")
      RESULT_TITLE_MAX_MS+=("-")
    fi

    # Store timer metrics (GCD and NS separately)
    RESULT_GCD_TIMER_CREATE+=("$gcd_timer_create")
    RESULT_GCD_TIMER_FIRE+=("$gcd_timer_fire")
    if [[ "$gcd_timer_create" -gt 0 ]]; then
      local gcd_ratio
      gcd_ratio=$(awk "BEGIN {printf \"%.1f\", $gcd_timer_fire / $gcd_timer_create}")
      RESULT_GCD_FIRE_RATIO+=("$gcd_ratio")
    else
      RESULT_GCD_FIRE_RATIO+=("-")
    fi
    RESULT_NS_TIMER_CREATE+=("$ns_timer_create")
    RESULT_NS_TIMER_FIRE+=("$ns_timer_fire")
    if [[ "$ns_timer_create" -gt 0 ]]; then
      local ns_ratio
      ns_ratio=$(awk "BEGIN {printf \"%.1f\", $ns_timer_fire / $ns_timer_create}")
      RESULT_NS_FIRE_RATIO+=("$ns_ratio")
    else
      RESULT_NS_FIRE_RATIO+=("-")
    fi

    # Store cadence mismatch percentage
    if [[ "$cadence_mismatch" -gt 0 || "$cadence_no_change" -gt 0 ]]; then
      local total_checks=$((cadence_mismatch + cadence_no_change))
      local mismatch_pct
      mismatch_pct=$(awk "BEGIN {printf \"%.1f\", 100 * $cadence_mismatch / $total_checks}")
      RESULT_CADENCE_MISMATCH_PCT+=("$mismatch_pct")
    else
      RESULT_CADENCE_MISMATCH_PCT+=("-")
    fi
  else
    # No latency file - store placeholders
    RESULT_KEYDOWN_MEAN_MS+=("-")
    RESULT_KEYDOWN_MAX_MS+=("-")
    RESULT_TITLE_MEAN_MS+=("-")
    RESULT_TITLE_MAX_MS+=("-")
    RESULT_GCD_TIMER_CREATE+=("-")
    RESULT_GCD_TIMER_FIRE+=("-")
    RESULT_GCD_FIRE_RATIO+=("-")
    RESULT_NS_TIMER_CREATE+=("-")
    RESULT_NS_TIMER_FIRE+=("-")
    RESULT_NS_FIRE_RATIO+=("-")
    RESULT_CADENCE_MISMATCH_PCT+=("-")
  fi

  # Wait a bit before next run to ensure clean state
  sleep 2
}

# Function to print summary table with Unicode box drawing
print_summary_table() {
  local num_runs=${#RESULT_TAB_COUNTS[@]}
  if [[ $num_runs -eq 0 ]]; then
    echo "No results to display"
    return
  fi

  # Calculate column widths
  local label_width=24
  local col_width=10

  # Build header row with tab counts (single-line box drawing)
  local header="│ Metric                   "
  local top_border="┌──────────────────────────"
  local header_sep="├──────────────────────────"
  local section_sep="├──────────────────────────"
  local bottom_border="└──────────────────────────"

  for i in "${!RESULT_TAB_COUNTS[@]}"; do
    local tc="${RESULT_TAB_COUNTS[$i]}"
    if [[ $tc -eq 1 ]]; then
      header+="│$(printf "%${col_width}s" "1 Tab")"
    else
      header+="│$(printf "%${col_width}s" "$tc Tabs")"
    fi
    top_border+="┬$(printf '─%.0s' $(seq 1 $col_width))"
    header_sep+="┼$(printf '─%.0s' $(seq 1 $col_width))"
    section_sep+="┼$(printf '─%.0s' $(seq 1 $col_width))"
    bottom_border+="┴$(printf '─%.0s' $(seq 1 $col_width))"
  done
  header+="│"
  top_border+="┐"
  header_sep+="┤"
  section_sep+="┤"
  bottom_border+="┘"

  echo "$top_border"
  echo "$header"
  echo "$header_sep"

  # Helper function to print a row
  print_row() {
    local label=$1
    shift
    local values=("$@")
    printf "│ %-${label_width}s " "$label"
    for val in "${values[@]}"; do
      printf "│%${col_width}s" "$val"
    done
    echo "│"
  }

  # Iteration stats (stress_load.py throughput)
  print_row "Iteration rate" "${RESULT_ITERATION_RATES[@]/%//s}"
  print_row "Total iterations" "${RESULT_TOTAL_ITERATIONS[@]}"

  # Latency metrics (from instrumentation)
  local has_latency=false
  for val in "${RESULT_KEYDOWN_MEAN_MS[@]}"; do
    [[ "$val" != "-" ]] && has_latency=true && break
  done
  if [[ "$has_latency" == true ]]; then
    echo "$section_sep"
    print_row "KeyDown mean (ms)" "${RESULT_KEYDOWN_MEAN_MS[@]}"
    print_row "KeyDown max (ms)" "${RESULT_KEYDOWN_MAX_MS[@]}"
    # Only show title latency if we have data
    local has_title=false
    for val in "${RESULT_TITLE_MEAN_MS[@]}"; do
      [[ "$val" != "-" ]] && has_title=true && break
    done
    if [[ "$has_title" == true ]]; then
      print_row "TitleUpdate mean (ms)" "${RESULT_TITLE_MEAN_MS[@]}"
      print_row "TitleUpdate max (ms)" "${RESULT_TITLE_MAX_MS[@]}"
    fi
  fi

  # Timer efficiency metrics (GCD and NS separately)
  local has_gcd_timer=false has_ns_timer=false
  for val in "${RESULT_GCD_FIRE_RATIO[@]}"; do
    [[ "$val" != "-" && "$val" != "0" ]] && has_gcd_timer=true && break
  done
  for val in "${RESULT_NS_FIRE_RATIO[@]}"; do
    [[ "$val" != "-" && "$val" != "0" ]] && has_ns_timer=true && break
  done
  if [[ "$has_gcd_timer" == true || "$has_ns_timer" == true ]]; then
    echo "$section_sep"
    if [[ "$has_gcd_timer" == true ]]; then
      print_row "GCD fire/create" "${RESULT_GCD_FIRE_RATIO[@]}"
    fi
    if [[ "$has_ns_timer" == true ]]; then
      print_row "NSTimer fire/create" "${RESULT_NS_FIRE_RATIO[@]}"
    fi
    print_row "Cadence mismatch %" "${RESULT_CADENCE_MISMATCH_PCT[@]}"
  fi

  # DTrace UX metrics (only if --dtrace was used)
  if [[ "$dtrace_mode" == true && ${#RESULT_REFRESHES[@]} -gt 0 ]]; then
    echo "$section_sep"
    print_row "Adaptive mode" "${RESULT_ADAPTIVE_MODE[@]}"
    print_row "Refresh FPS" "${RESULT_REFRESH_FPS[@]}"
    print_row "Metal FPS" "${RESULT_METAL_FPS[@]}"
    print_row "Iters/frame" "${RESULT_ITERS_PER_FRAME[@]}"
    echo "$section_sep"
    print_row "Refreshes" "${RESULT_REFRESHES[@]}"
    print_row "Metal frames" "${RESULT_METAL_FRAMES[@]}"
    print_row "Content updates" "${RESULT_CONTENT_FRAMES[@]}"
    echo "$section_sep"
    print_row "Join calls" "${RESULT_JOIN_CALLS[@]}"
    print_row "Join time (us)" "${RESULT_JOIN_TIME_US[@]}"
  fi

  echo "$bottom_border"
  echo ""
  echo "Legend:"
  echo "  Iteration rate   - stress_load.py output lines/sec (terminal throughput)"
  if [[ "$has_latency" == true ]]; then
    echo "  KeyDown          - Latency from keypress to screen update (ms)"
    if [[ "$has_title" == true ]]; then
      echo "  TitleUpdate      - Latency for OSC 0 title change processing (ms)"
    fi
  fi
  if [[ "$has_gcd_timer" == true || "$has_ns_timer" == true ]]; then
    [[ "$has_gcd_timer" == true ]] && echo "  GCD fire/create  - GCD timer fires per create (higher = better reuse)"
    [[ "$has_ns_timer" == true ]] && echo "  NSTimer fire/create - NSTimer fires per create (higher = better reuse)"
    echo "  Cadence mismatch - % of cadence checks with timing drift"
  fi
  if [[ "$dtrace_mode" == true ]]; then
    echo "  Adaptive mode    - Frame rate mode (60fps=low load, 30fps=high load)"
    echo "  Refresh FPS      - Cadence-driven refresh rate"
    echo "  Metal FPS        - GPU frame submissions/sec"
    echo "  Iters/frame      - Stress iterations per Metal frame (throughput)"
    echo "  Refreshes        - Total cadence-driven refresh calls"
    echo "  Metal frames     - Total GPU frame submissions"
    echo "  Content updates  - Lines marked dirty (setNeedsDisplayOnLine calls)"
    echo "  Join calls       - performBlockWithJoinedThreads calls (thread sync)"
    echo "  Join time        - Total time in joined blocks (microseconds)"
  fi
}

# Function to run forever mode (no profiling, no data collection)
run_forever() {
  local tab_count=${tab_counts[0]}  # Use first tab count only

  echo ""
  echo "Forever mode: $tab_count tab(s), no profiling"

  # Warn about tmux + forever combination
  if [[ "$tmux_mode" == true ]]; then
    echo ""
    echo "WARNING: --tmux with --forever mode cannot guarantee session cleanup."
    echo "         tmux sessions will run until manually stopped."
    echo "         Press Ctrl-C to attempt cleanup of tmux sessions and iTerm2."
    echo ""
  fi

  # Video mode not supported with forever mode
  if [[ "$video_mode" == true ]]; then
    echo ""
    echo "WARNING: --video is not supported with --forever mode (requires fixed duration)."
    echo "         Use macOS screen recording (Cmd-Shift-5) for manual recording."
    echo ""
  fi

  # Open iTerm2 and wait for it to launch
  # Launch iTerm2 with suite isolation
  if [[ -n "$suite_name" ]]; then
    open -a "$app_path" --args -suite "$suite_name"
  else
    open -a "$app_path"
  fi
  sleep 2

  # Find iTerm2 PID
  local iterm_pid=""
  for _ in {1..10}; do
    iterm_pid=$(pgrep -x iTerm2 || true)
    if [[ -n "$iterm_pid" ]]; then
      break
    fi
    sleep 0.5
  done

  if [[ -z "$iterm_pid" ]]; then
    echo "Error: Could not find iTerm2 process" >&2
    exit 1
  fi

  echo "Found iTerm2 PID: $iterm_pid"
  echo "Launching $tab_count tabs with stress load..."

  # Generate unique tmux session prefix if --tmux mode
  local tmux_prefix=""
  if [[ "$tmux_mode" == true ]]; then
    tmux_prefix="iterm2-perf-$$-$(date +%s)"
    tmux_session_prefix="$tmux_prefix"  # Store globally for cleanup
    tmux_tab_count="$tab_count"
  fi

  # Launch tabs (runs in background)
  osascript "$applescript_forever_file" "$tab_count" "$load_script" "$stress_mode" "$title_arg" "$speed_arg" "$fps_arg" "$tmux_prefix" &
  local applescript_pid=$!

  # Wait for AppleScript to finish launching tabs
  wait "$applescript_pid" || true

  echo ""
  echo "Stress load running."
}

# Capture power information at script start
power_source=$(get_power_source)
energy_mode=$(get_energy_mode)

# Main execution
echo "Multi-Tab Stress Test"
echo "====================="
echo "App: $app_path"
echo "Version: $app_version"
if [[ -n "$build_commit" ]]; then
  echo "Commit: ${build_commit:0:12}"
  [[ -n "$build_branch" ]] && echo "Branch: $build_branch"
  [[ -n "$build_date" ]] && echo "Build date: $build_date"
  [[ "$build_uncommitted" == "true" ]] && echo "Uncommitted changes: yes"
fi
echo "Power Source: $power_source"
echo "Energy Mode: $energy_mode"

# Check if using isolated suite (not user's normal prefs)
using_isolated_suite=false
if [[ -n "$suite_name" && "$suite_name" != "com.googlecode.iterm2" ]]; then
  using_isolated_suite=true
fi

# Warn if not on AC power, not in high performance mode, or not using isolated suite
if [[ "$power_source" != "AC Power" || "$energy_mode" != "High Power/High Performance" || "$using_isolated_suite" == false ]]; then
  echo ""
  echo "WARNING: Performance testing should use standard conditions for reliable results!"
  echo ""
  echo "         Current issues:"
  [[ "$power_source" != "AC Power" ]] && echo "           - Running on $power_source (not AC Power)"
  [[ "$energy_mode" != "High Power/High Performance" ]] && echo "           - Energy Mode: $energy_mode (not High Power/High Performance)"
  [[ "$using_isolated_suite" == false ]] && echo "           - Not using isolated suite (user prefs may affect results)"
  echo ""
  echo "         These conditions may produce unreliable or unexpected performance results."
  echo ""
  echo "         Recommendations:"
  [[ "$power_source" != "AC Power" ]] && echo "           - Connect to AC Power"
  [[ "$energy_mode" != "High Power/High Performance" ]] && echo "           - Set Energy Mode to High Power/High Performance"
  [[ "$using_isolated_suite" == false ]] && echo "           - Use isolated suite (default: --suite=com.iterm2.defaults)"
  echo ""
fi

if [[ "$forever_mode" == true ]]; then
  echo "Mode: forever (no profiling)"
else
  echo "Duration: ${duration}s"
fi
echo "Tab counts: ${tab_counts[*]}"
echo "Synchronized start: $synchronized_start"
echo "Inject interactions: $inject_mode"
echo "DTrace mode: $dtrace_mode"
echo "Self-time profiling: $self_time_mode"
echo "Tmux wrapped: $tmux_mode"
echo "Video recording: $video_mode"
[[ "$video_mode" == true ]] && echo "Video output dir: $video_output_dir"
echo "Speed: $speed_arg"
if [[ -n "$suite_name" ]]; then
  echo "Suite: $suite_name"
else
  echo "Suite: (none - using user preferences)"
fi
if [[ -n "$stress_mode" ]]; then
  echo "Mode: ${stress_mode#--mode=}"
fi
echo "Load script: $(basename "$load_script")"
[[ -n "$title_arg" ]] && echo "Title injection: ${title_arg}ms"

# Run forever mode or normal mode
if [[ "$forever_mode" == true ]]; then
  run_forever
else
  # Run tests for each tab count
  for i in "${!tab_counts[@]}"; do
    run_single_test "${tab_counts[$i]}" "$i"
  done

  # Print summary table if multiple runs
  if [[ ${#tab_counts[@]} -gt 1 ]]; then
    echo ""
    echo "Summary Table"
    print_summary_table
  fi

  # Repeat warning at end if not on AC power, not in high performance mode, or not using isolated suite
  if [[ "$power_source" != "AC Power" || "$energy_mode" != "High Power/High Performance" || "$using_isolated_suite" == false ]]; then
    echo ""
    echo "============================================================"
    echo "WARNING: These results may not reflect optimal performance!"
    echo "============================================================"
    echo ""
    echo "Issues detected:"
    [[ "$power_source" != "AC Power" ]] && echo "  - Power Source: $power_source (not AC Power)"
    [[ "$energy_mode" != "High Power/High Performance" ]] && echo "  - Energy Mode: $energy_mode (not High Power/High Performance)"
    [[ "$using_isolated_suite" == false ]] && echo "  - Not using isolated suite (user prefs may affect results)"
    echo ""
    echo "Performance testing should use standard conditions for reliable results."
    echo "Current configuration may produce unreliable or unexpected performance."
    echo ""
    echo "Recommendations:"
    [[ "$power_source" != "AC Power" ]] && echo "  - Connect to AC Power"
    [[ "$energy_mode" != "High Power/High Performance" ]] && echo "  - Set Energy Mode to High Power/High Performance"
    [[ "$using_isolated_suite" == false ]] && echo "  - Use isolated suite (default: --suite=com.iterm2.defaults)"
    echo "============================================================"
  fi
fi
