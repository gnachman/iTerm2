# iTerm2 Performance Testing Tools

Scripts for stress testing and profiling iTerm2 builds with latency instrumentation.

## Quick Start

```bash
# Basic test (10 tabs, 20 seconds, normal mode)
./run_stress_test.sh /path/to/iTerm2.app

# Compare behavior across tab counts
./run_stress_test.sh --tabs=1,3,10 /path/to/iTerm2.app

# With title injection (exercises OSC 0 handling)
./run_stress_test.sh --title /path/to/iTerm2.app

# With DTrace metrics (requires sudo)
./run_stress_test.sh --dtrace /path/to/iTerm2.app

# With tmux wrapping (cleanup attempted)
./run_stress_test.sh --tmux /path/to/iTerm2.app

# htop-style dashboard load
./run_stress_test.sh --mode=htop /path/to/iTerm2.app

# Progress bars stress test
./run_stress_test.sh --mode=progress /path/to/iTerm2.app

# Status grid with tmux wrapping
./run_stress_test.sh --tmux --mode=status /path/to/iTerm2.app
```

## Scripts

| Script | Purpose |
|--------|---------|
| `run_stress_test.sh` | Main test harness - opens iTerm2, creates tabs, runs stress load, profiles |
| `stress_load.py` | Unified load generator - terminal output stress and dashboard modes |
| `analyze_profile.py` | Analyzes `sample` profiler output for hotspots |
| `analyze_self_time.py` | Analyzes self-time profiler output, filters non-actionable symbols |
| `iterm_ux_metrics_v2.d` | DTrace script for frame rate and latency metrics |
| `iterm_self_time.d` | DTrace script for self-time (exclusive time) profiling |

## Options

```
-t, --time=SEC    Duration in seconds (default: 20)
--tabs=N,M,...    Tab counts to test (runs separate test for each)
--title[=MS]      Inject OSC 0 title changes (default: every 2000ms)
--fps=N           Target frame rate for dashboard modes (default: 30, 0 = unthrottled)
                  Accepts decimals (e.g., 0.5). Ignored for stress modes.
--dtrace          Enable DTrace UX metrics (requires sudo)
--self-time       Enable self-time profiling (requires sudo, see below)
--inject          Enable continuous responsiveness testing (see below)
--mode=MODES      Stress mode(s), comma-separated (see Modes below)
--speed=SPEED     Output speed: normal or slow
--tmux            Wrap test in auto-cleanup tmux session
--load-script=PATH  Use custom load generator (for non-built-in scripts)
--suite=NAME      Use isolated UserDefaults suite (default: com.iterm2.defaults)
                  --suite=user uses normal iTerm2 preferences
                  --suite=none disables suite isolation
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
./run_stress_test.sh --mode=htop,watch,progress,table,status --fps=120 -t 50 /path/to/iTerm2.app

# Mix stress and dashboard modes
./run_stress_test.sh --mode=normal,htop,buffer -t 30 /path/to/iTerm2.app

# Dashboard unthrottled (as fast as possible)
./run_stress_test.sh --mode=htop --fps=0 /path/to/iTerm2.app
```

## Responsiveness Testing

The `--inject` option enables continuous interaction injection to measure UI responsiveness
under load. This exercises the latency instrumentation code paths throughout the test:

| Event Type | Interval | Purpose |
|------------|----------|---------|
| Keyboard input | 500ms | Single character input to measure key-to-screen latency |
| Scroll events | 2s | Page Up/Down alternating to test scroll responsiveness |
| Tab switches | 3s | Cycles through all tabs to test tab change latency |

### Example

```bash
# Run stress test with responsiveness injection
./run_stress_test.sh --inject /path/to/iTerm2.app

# Combined with title injection for OSC handling
./run_stress_test.sh --inject --title /path/to/iTerm2.app

# Full instrumentation with DTrace
sudo ./run_stress_test.sh --inject --dtrace /path/to/iTerm2.app
```

The injection summary is printed at test completion showing event counts.

## Self-Time Profiling

The `--self-time` option enables DTrace-based profiling that shows "self time" - the time
functions actually spend executing their own code, not time spent in functions they call.

This is more actionable than total/inclusive time because:
- Functions like `main()` appear at the top of every call stack but do no real work
- High-level callers (like event loops) dominate inclusive time
- Self-time shows which functions actually burn CPU

### Example

```bash
# Run stress test with self-time profiling
sudo ./run_stress_test.sh --self-time /path/to/iTerm2.app

# Combined with other options
sudo ./run_stress_test.sh --self-time --dtrace --tabs=5,10 /path/to/iTerm2.app
```

### Output

The analysis script filters results into categories:
- **Actionable iTerm2 functions** - Code you can optimize
- **System hotspots** - Runtime overhead (objc_msgSend, malloc) for awareness
- **Other code** - Libraries and frameworks

High system overhead (>40%) suggests opportunities like:
- Batching operations to reduce objc_msgSend calls
- Object pooling to reduce malloc/free
- Caching to reduce repeated lookups

### Scripts

| Script | Purpose |
|--------|---------|
| `iterm_self_time.d` | DTrace script using profile provider at 997Hz |
| `analyze_self_time.py` | Parses output, filters non-actionable symbols |

## Tmux Wrapping

The `--tmux` option wraps the entire test in a tmux session that auto-cleans on exit:
- Session is killed on normal exit, Ctrl-C, or crash
- Prevents orphaned stress processes if the harness is killed
- Session name: `iterm2-perf-<pid>-<timestamp>`
- Interactive: attaches to session for live viewing
- Non-interactive: waits for session to complete

## Suite Presets

The `suites/` directory contains plist files for reproducible test configurations.
These are used with the `--suite=` option which isolates preferences via NSUserDefaults suites.

### Available Suites

| Suite | Purpose |
|-------|---------|
| `com.iterm2.defaults` | Empty suite for clean default behavior |
| `com.iterm2.fairness` | Enables `useFairnessScheduler` (requires PR #568) |

### Installation

Manually copy the desired suite to `~/Library/Preferences/`:

```bash
cp tools/perf/suites/com.iterm2.fairness.plist ~/Library/Preferences/
```

### Usage

```bash
# Test with fairness scheduler enabled
./run_stress_test.sh --suite=com.iterm2.fairness /path/to/iTerm2.app

# Test with clean defaults
./run_stress_test.sh --suite=com.iterm2.defaults /path/to/iTerm2.app

# Default: com.iterm2.defaults (auto-created empty suite for isolation)
./run_stress_test.sh /path/to/iTerm2.app
```

Suite plists are stored separately from your normal iTerm2 preferences (`com.googlecode.iterm2.plist`),
so testing with different suites won't affect your personal settings.

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
