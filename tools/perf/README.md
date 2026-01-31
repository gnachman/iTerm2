# iTerm2 Performance Testing Tools

Scripts for stress testing and profiling iTerm2 builds with latency instrumentation.

## Quick Start

```bash
# Basic test (10 tabs, 20 seconds, normal mode)
./run_multi_tab_stress_test.sh /path/to/iTerm2.app

# Compare behavior across tab counts
./run_multi_tab_stress_test.sh --tabs=1,3,10 /path/to/iTerm2.app

# With title injection (exercises OSC 0 handling)
./run_multi_tab_stress_test.sh --title /path/to/iTerm2.app

# With DTrace metrics (requires sudo)
./run_multi_tab_stress_test.sh --dtrace /path/to/iTerm2.app

# With tmux wrapping (crash-safe cleanup)
./run_multi_tab_stress_test.sh --tmux /path/to/iTerm2.app

# Htop-style dashboard load
./run_multi_tab_stress_test.sh --mode=htop /path/to/iTerm2.app

# Progress bars stress test
./run_multi_tab_stress_test.sh --mode=progress /path/to/iTerm2.app

# Status grid with tmux wrapping
./run_multi_tab_stress_test.sh --tmux --mode=status /path/to/iTerm2.app
```

## Scripts

| Script | Purpose |
|--------|---------|
| `run_multi_tab_stress_test.sh` | Main test harness - opens iTerm2, creates tabs, runs stress load, profiles |
| `stress_load.py` | Unified load generator - terminal output stress and dashboard modes |
| `analyze_profile.py` | Analyzes `sample` profiler output for hotspots |
| `iterm_ux_metrics_v2.d` | DTrace script for frame rate and latency metrics |

## Options

```
-t, --time=SEC    Duration in seconds (default: 20)
--tabs=N,M,...    Tab counts to test (runs separate test for each)
--title[=MS]      Inject OSC 0 title changes (default: every 2000ms)
--fps=N           Target frame rate for dashboard modes (default: 30, 0 = unthrottled)
                  Accepts decimals (e.g., 0.5). Ignored for stress modes.
--dtrace          Enable DTrace UX metrics (requires sudo)
--inject          Enable interaction injection (tab switches, keyboard input)
--mode=MODES      Stress mode(s), comma-separated (see Modes below)
--speed=SPEED     Output speed: normal or slow
--tmux            Wrap test in auto-cleanup tmux session
--load-script=PATH  Use custom load generator (for non-built-in scripts)
--forever         Run indefinitely without profiling
```

## Modes

The `--mode` flag selects the stress pattern. Multiple modes can be comma-separated
and will run sequentially, time-sliced within a single test.

### Terminal Output Stress (unthrottled)

| Mode | Description |
|------|-------------|
| `normal` | Mixed output patterns (ASCII, CJK, emoji, bidi), no screen clears (default) |
| `buffer` | Long lines (~600 chars), stresses line buffer handling |
| `clearcodes` | All patterns including screen clear/erase sequences |
| `flood` | Maximum throughput using `yes` command |

### Dashboard/UI Stress (throttled by --fps, default 30)

| Mode | Description | Code Paths Stressed |
|------|-------------|---------------------|
| `htop` | CPU meters + scrolling process list | Scroll regions, partial updates, color bars |
| `watch` | Full-screen clear + redraw | Burst rendering, screen clear, cursor home |
| `progress` | 20 progress bars updating in place | Cursor positioning, same-line overwrites |
| `table` | Fixed header + scroll region body | Scroll regions, selective scroll |
| `status` | Grid of color-coded service status cells | Frequent SGR changes, partial cell updates |

### Special

| Mode | Description |
|------|-------------|
| `all` | Runs all 8 modes sequentially within a single test |

### Examples

```bash
# All dashboard modes at 120fps
./run_multi_tab_stress_test.sh --mode=htop,watch,progress,table,status --fps=120 -t 50 /path/to/iTerm2.app

# Mix stress and dashboard modes
./run_multi_tab_stress_test.sh --mode=normal,htop,buffer -t 30 /path/to/iTerm2.app

# Dashboard unthrottled (as fast as possible)
./run_multi_tab_stress_test.sh --mode=htop --fps=0 /path/to/iTerm2.app
```

## Tmux Wrapping

The `--tmux` option wraps the entire test in a tmux session that auto-cleans on exit:
- Session is killed on normal exit, Ctrl-C, or crash
- Prevents orphaned stress processes if the harness is killed
- Session name: `iterm2-perf-<pid>-<timestamp>`
- Interactive: attaches to session for live viewing
- Non-interactive: waits for session to complete

## Output

The test produces:
- **Profile analysis** - CPU hotspots from `sample` profiler
- **Latency metrics** - KeyboardInput, TitleUpdate timings (from instrumented builds)
- **Timer analysis** - GCD/NSTimer efficiency, cadence stability
- **DTrace metrics** - Frame rates, adaptive mode, lock contention (if --dtrace)
- **Summary table** - Cross-run comparison when testing multiple tab counts

## Requirements

- macOS with `sample` profiler
- Python 3
- For --tmux: tmux installed
- For --dtrace: sudo access
- Instrumented iTerm2 build (for latency metrics)
