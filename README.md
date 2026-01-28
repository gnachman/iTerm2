> **Fork Note:** This fork's [`instrumentation-only`](https://github.com/chall37/iTerm2/tree/instrumentation-only) branch provides performance testing infrastructure for iTerm2.
>
> ### Quick Start
>
> ```bash
> # Basic test (10 tabs, 20 seconds)
> ./tools/perf/run_multi_tab_stress_test.sh /path/to/iTerm2.app
>
> # Compare behavior across tab counts
> ./tools/perf/run_multi_tab_stress_test.sh --tabs=1,3,10 /path/to/iTerm2.app
>
> # With DTrace metrics (requires sudo)
> ./tools/perf/run_multi_tab_stress_test.sh --dtrace /path/to/iTerm2.app
> ```
>
> ### Scripts
>
> | Script | Purpose |
> |--------|---------|
> | `run_multi_tab_stress_test.sh` | Main test harness - opens iTerm2, creates tabs, runs stress load, profiles |
> | `stress_load.py` | Generates terminal output to stress rendering |
> | `analyze_profile.py` | Analyzes `sample` profiler output for hotspots |
> | `iterm_ux_metrics_v2.d` | DTrace script for frame rate and latency metrics |
>
> ### Output
>
> - **Profile analysis** - CPU hotspots from `sample` profiler
> - **Latency metrics** - KeyboardInput, TitleUpdate timings (from instrumented builds)
> - **Timer analysis** - GCD/NSTimer efficiency, cadence stability
> - **DTrace metrics** - Frame rates, adaptive mode, lock contention (if --dtrace)
> - **Summary table** - Cross-run comparison when testing multiple tab counts

<div align="center">

# iTerm2

### macOS Terminal Replacement

![Version](https://img.shields.io/badge/version-3.6-blue.svg)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)

**[Website](https://iterm2.com)** • **[Downloads](https://iterm2.com/downloads.html)** • **[Documentation](https://iterm2.com/documentation.html)** • **[Features](https://iterm2.com/features.html)**

</div>

---

## About

iTerm2 is a powerful terminal emulator for macOS that brings the terminal into the modern age with features you never knew you always wanted.

### Key Features

- **tmux Integration** - Native iTerm2 windows/tabs replace tmux's text-based interface. Run tmux -CC and tmux windows become real macOS windows. Sessions persist through crashes, SSH disconnects, and even app upgrades. Collaborate by having two people attach to the same session.
- **Shell Integration** - Deep shell awareness that tracks commands, directories, hostnames, and usernames. Enables click-to-download files via SCP, drag-and-drop uploads, command history per host, recent directories by "frecency," and marks at each prompt.
- **AI Chat** - Built-in LLM chat window that can optionally interact with terminal contents. Link sessions to get context-aware help, run commands on your behalf, or explain output with annotations.
- **Inline Images** - Display images (including animated GIFs) directly in the terminal. Use imgcat to view photos, charts, or visual output without leaving your workflow.
- **Automatic Profile Switching** - Terminal appearance changes automatically based on hostname, username, directory, or running command. SSH to production? Background turns red. Different environments get different visual contexts.
- **Dedicated Hotkey Windows** - System-wide hotkey summons a terminal that slides down from the top of the screen (or any edge), even over fullscreen apps. Pin it or let it auto-hide.
- **Session Restoration** - Sessions run in long-lived server processes. If iTerm2 crashes or upgrades, your shells keep running. When iTerm2 restarts, it reconnects to your sessions exactly where you left off.
- **Built-in Web Browser** - Browser profiles integrate web browsing into iTerm2's window/tab/pane hierarchy. Copy mode, triggers, AI chat, and other terminal features work in browser sessions.
- **Configurable Status Bar** - Per-session status bar showing git branch, CPU/memory graphs, current directory, hostname, custom interpolated strings, or Python API components.
- **Triggers** - Regex patterns that fire actions when matched: highlight text, run commands, send notifications, open password manager, set marks, or invoke Python scripts.
- **Smart Selection** - Quad-click selects semantic objects (URLs, file paths, email addresses, quoted strings). Right-click for context actions. Cmd-click to open.
- **Copy Mode** - Vim-like keyboard selection. Navigate and select text without touching the mouse. Works with marks to jump between command prompts.
- **Instant Replay** - Scrub backward through terminal history to see exactly what was on screen at any moment, with timestamps. Perfect for catching fleeting errors.
- **Python Scripting API** - Full automation and customization via Python. Create custom status bar components, triggers, menu items, or entirely new features.
- **Open Quickly** - Cmd-Shift-O opens a search across all sessions by tab title, command, hostname, directory, or badge. Navigate large session collections instantly.

---

## Installation

### Download
Get the latest version from [iterm2.com/downloads](https://iterm2.com/downloads.html)

### Build from Source
See our [build guide](https://gitlab.com/gnachman/iterm2/wikis/HowToBuild) for detailed instructions.

---

## Development

### Building

```bash
# Clone the repository
git clone https://github.com/gnachman/iTerm2.git
cd iTerm2

# Build with Xcode
xcodebuild -project iTerm2.xcodeproj -scheme iTerm2 -configuration Debug
```

### Contributing

We welcome contributions! Please read our [contribution guide](https://gitlab.com/gnachman/iterm2/-/wikis/How-to-Contribute) before submitting pull requests.

---

## Bug Reports & Issues

- **File bugs:** [iterm2.com/bugs](https://iterm2.com/bugs)
- **Issue tracker:** [GitLab Issues](https://gitlab.com/gnachman/iterm2/issues)

> **Note:** We use GitLab for issues because it provides better support for attachments.

---

## Resources

| Resource | Link |
|----------|------|
| Official Website | [iterm2.com](https://iterm2.com) |
| Documentation | [iterm2.com/documentation](https://iterm2.com/documentation.html) |
| Community | [iTerm2 Discussions](https://gitlab.com/gnachman/iterm2/-/issues) |
| Downloads | [iterm2.com/downloads](https://iterm2.com/downloads.html) |

---

## License

iTerm2 is distributed under the [GPLv3](LICENSE) license.

---

## Support

If you love iTerm2, consider:
- Starring this repository
- Spreading the word
- [Sponsoring development](https://iterm2.com/donate.html)

---

<div align="center">

**Made by [George Nachman](https://github.com/gnachman) and [contributors](https://github.com/gnachman/iTerm2/graphs/contributors)**

</div>
