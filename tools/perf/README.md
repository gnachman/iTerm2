# iTerm2 Performance Testing Tools

Scripts for stress testing and profiling iTerm2 builds with latency instrumentation.

## Quick Start

```bash
# Basic test (10 tabs, 20 seconds)
./run_multi_tab_stress_test.sh /path/to/iTerm2.app

# Compare behavior across tab counts
./run_multi_tab_stress_test.sh --tabs=1,3,10 /path/to/iTerm2.app

# With title injection (exercises OSC 0 handling)
./run_multi_tab_stress_test.sh --title /path/to/iTerm2.app

# With DTrace metrics (requires sudo)
./run_multi_tab_stress_test.sh --dtrace /path/to/iTerm2.app

# With tmux wrapping (crash-safe cleanup)
./run_multi_tab_stress_test.sh --tmux /path/to/iTerm2.app

# Htop-style dashboard load (default mode)
./run_multi_tab_stress_test.sh --load-script=load_dashboard.py --mode=htop /path/to/iTerm2.app

# Progress bars stress test
./run_multi_tab_stress_test.sh --load-script=load_dashboard.py --mode=progress /path/to/iTerm2.app

# Status grid with tmux wrapping
./run_multi_tab_stress_test.sh --tmux --load-script=load_dashboard.py --mode=status /path/to/iTerm2.app
```

## Scripts

| Script | Purpose |
|--------|---------|
| `run_multi_tab_stress_test.sh` | Main test harness - opens iTerm2, creates tabs, runs stress load, profiles |
| `stress_load.py` | Generates terminal output to stress rendering |
| `load_dashboard.py` | Dashboard/htop-style load generator with cursor positioning |
| `analyze_profile.py` | Analyzes `sample` profiler output for hotspots |
| `iterm_ux_metrics_v2.d` | DTrace script for frame rate and latency metrics |
| `tmux_wrapper.sh` | Library for auto-cleanup tmux session wrapping |

## Options

```
--tabs=N,M,...    Tab counts to test (runs separate test for each)
--title[=MS]      Inject OSC 0 title changes (default: every 2000ms)
--dtrace          Enable DTrace UX metrics (requires sudo)
--inject          Enable interaction injection (tab switches, keyboard input)
--mode=MODE       Stress mode: normal, buffer, clearcodes, all
--speed=SPEED     Output speed: normal or slow
--tmux            Wrap test in auto-cleanup tmux session
--load-script=PATH  Use custom load generator (default: stress_load.py)
--forever         Run indefinitely without profiling
```

## Load Generators

### stress_load.py (default)
Generates various terminal output patterns to exercise text processing:
- Plain ASCII, ANSI colors, wide characters (CJK)
- RTL text (bidi processing), emoji, combining characters
- Control characters, hyperlinks, box drawing

### load_dashboard.py
Dashboard-style displays that stress cursor positioning and partial updates.
Runs at ~30fps, uses alternate screen mode (restores terminal on exit).

| Mode | Description | Code Paths Stressed |
|------|-------------|---------------------|
| `htop` | CPU meters + scrolling process list | Scroll regions, partial updates, color bars |
| `watch` | Full-screen clear + redraw every 100ms | Burst rendering, screen clear, cursor home |
| `progress` | 20 progress bars updating in place | Cursor positioning, same-line overwrites |
| `table` | Fixed header + scroll region body | Scroll regions, selective scroll |
| `status` | Grid of color-coded service status | Frequent SGR changes, partial cell updates |

Usage: `--load-script=load_dashboard.py --mode=htop`

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
