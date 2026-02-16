#!/usr/bin/env python3
"""
Generate terminal load for stress testing iTerm2.

Usage:
    python3 stress_load.py [duration_seconds] [label] [--sync-dir DIR] [--mode=MODE] [--title] [--speed=SPEED]

This script generates various types of terminal output to exercise
iTerm2's rendering and text processing code paths. It does NOT run
a profiler - use this with run_stress_test.sh for multi-tab
profiled stress testing, or profile_stress_test.py for single-tab use.

With --sync-dir, the script signals readiness and waits for a "go"
signal before starting, allowing synchronized startup across tabs.

Options:
    --title[=MS]  Inject OSC 0 title changes every MS milliseconds (default 2000ms)
    --speed=SPEED Output speed: normal (default) or slow (100ms delay per iteration)
    --fps=N       Target frame rate for dashboard modes (default 30, 0 = unthrottled)
                  Accepts decimals (e.g., 0.5 for one frame per 2 seconds).
                  Ignored for stress modes which always run unthrottled.

Terminal output stress modes:
    normal     - mixed output patterns, no screen clears (default)
    buffer     - long lines (~600 chars), stresses line buffers
    clearcodes - all patterns including clear/erase sequences
    flood      - maximum throughput, like 'yes' command (no throttling)

Dashboard/UI stress modes (30fps, cursor positioning):
    htop       - CPU meters + scrolling process list
    watch      - full-screen clear + redraw every 100ms
    progress   - 20 progress bars updating in place
    table      - fixed header + scroll region body
    status     - grid of color-coded service status cells

Special:
    all        - runs all modes sequentially (separate test per mode)
"""

import os
import random
import shutil
import subprocess
import sys
import time
import threading
from pathlib import Path


# =============================================================================
# ANSI escape sequences for dashboard modes
# =============================================================================

ESC = "\033"
CSI = f"{ESC}["

# Colors
RESET = f"{CSI}0m"
BOLD = f"{CSI}1m"
DIM = f"{CSI}2m"
REVERSE = f"{CSI}7m"

# Foreground colors
FG_BLACK = f"{CSI}30m"
FG_RED = f"{CSI}31m"
FG_GREEN = f"{CSI}32m"
FG_YELLOW = f"{CSI}33m"
FG_BLUE = f"{CSI}34m"
FG_MAGENTA = f"{CSI}35m"
FG_CYAN = f"{CSI}36m"
FG_WHITE = f"{CSI}37m"

# Background colors
BG_BLACK = f"{CSI}40m"
BG_RED = f"{CSI}41m"
BG_GREEN = f"{CSI}42m"
BG_YELLOW = f"{CSI}43m"
BG_BLUE = f"{CSI}44m"
BG_MAGENTA = f"{CSI}45m"
BG_CYAN = f"{CSI}46m"
BG_WHITE = f"{CSI}47m"


def cursor_home():
    return f"{CSI}H"

def cursor_to(row, col):
    return f"{CSI}{row};{col}H"

def cursor_hide():
    return f"{CSI}?25l"

def cursor_show():
    return f"{CSI}?25h"

def clear_screen():
    return f"{CSI}2J"

def clear_line():
    return f"{CSI}2K"

def clear_to_eol():
    return f"{CSI}K"

def set_scroll_region(top, bottom):
    return f"{CSI}{top};{bottom}r"

def reset_scroll_region():
    return f"{CSI}r"

def enter_alt_screen():
    return f"{CSI}?1049h"

def exit_alt_screen():
    return f"{CSI}?1049l"


def get_terminal_size():
    """Get terminal dimensions."""
    size = shutil.get_terminal_size(fallback=(80, 24))
    return size.columns, size.lines


def progress_bar(value, width, filled_char="█", empty_char="░", color_thresholds=None):
    """Generate a progress bar string."""
    inner_width = width - 2
    filled = int(value * inner_width)
    empty = inner_width - filled

    color = FG_GREEN
    if color_thresholds:
        for threshold, c in color_thresholds:
            if value >= threshold:
                color = c

    return f"[{color}{filled_char * filled}{RESET}{empty_char * empty}]"


def generate_fake_process():
    """Generate a fake process entry for htop-style display."""
    pid = random.randint(1, 99999)
    user = random.choice(["root", "admin", "www-data", "postgres", "_windowserver", "daemon"])
    cpu = random.uniform(0, 100)
    mem = random.uniform(0, 50)
    commands = [
        "python3 stress_load.py", "/usr/bin/sample iTerm2", "iTerm2 --server",
        "/System/Library/Metal", "WindowServer", "mds_stores", "kernel_task",
        "launchd", "sshd: admin", "vim /etc/hosts", "docker compose up",
        "node server.js", "postgres: writer",
    ]
    command = random.choice(commands)

    if cpu > 80:
        cpu_color = FG_RED
    elif cpu > 50:
        cpu_color = FG_YELLOW
    else:
        cpu_color = FG_GREEN

    return {"pid": pid, "user": user, "cpu": cpu, "mem": mem,
            "command": command, "cpu_color": cpu_color}


# =============================================================================
# Dashboard mode classes
# =============================================================================

class DashboardMode:
    """Base class for dashboard modes."""

    def __init__(self, label=""):
        self.label = label
        self.iteration = 0
        self.width, self.height = get_terminal_size()

    def setup(self):
        pass

    def update(self):
        self.iteration += 1
        return ""

    def teardown(self):
        pass


class HtopMode(DashboardMode):
    """Htop-style display with CPU meters and process list."""

    def __init__(self, label=""):
        super().__init__(label)
        self.cpu_count = min(8, (self.height - 10) // 2)
        self.cpu_values = [random.uniform(0, 1) for _ in range(self.cpu_count)]
        self.mem_value = random.uniform(0.3, 0.7)
        self.swap_value = random.uniform(0, 0.3)
        self.processes = [generate_fake_process() for _ in range(50)]
        self.header_lines = 3 + self.cpu_count + 2

    def setup(self):
        print(enter_alt_screen() + cursor_hide() + clear_screen(), end="", flush=True)

    def update(self):
        self.iteration += 1
        output = [cursor_home()]

        for i in range(self.cpu_count):
            self.cpu_values[i] = max(0, min(1, self.cpu_values[i] + random.uniform(-0.1, 0.1)))

        self.mem_value = max(0.1, min(0.95, self.mem_value + random.uniform(-0.02, 0.02)))
        self.swap_value = max(0, min(0.5, self.swap_value + random.uniform(-0.01, 0.01)))

        bar_width = min(40, self.width - 20)

        for i in range(self.cpu_count):
            bar = progress_bar(self.cpu_values[i], bar_width,
                             color_thresholds=[(0.5, FG_YELLOW), (0.8, FG_RED)])
            output.append(f"{clear_line()}CPU{i}: {bar} {self.cpu_values[i]*100:5.1f}%\n")

        mem_bar = progress_bar(self.mem_value, bar_width, color_thresholds=[(0.7, FG_YELLOW), (0.9, FG_RED)])
        swap_bar = progress_bar(self.swap_value, bar_width, color_thresholds=[(0.5, FG_YELLOW), (0.8, FG_RED)])
        output.append(f"{clear_line()}Mem: {mem_bar} {self.mem_value*100:5.1f}%\n")
        output.append(f"{clear_line()}Swp: {swap_bar} {self.swap_value*100:5.1f}%\n")
        output.append(f"{clear_line()}{BOLD}{REVERSE} PID    USER      CPU%  MEM%  COMMAND{' ' * (self.width - 45)}{RESET}\n")

        process_lines = self.height - self.header_lines - 2
        for _ in range(5):
            self.processes[random.randint(0, len(self.processes) - 1)] = generate_fake_process()

        sorted_procs = sorted(self.processes, key=lambda p: p["cpu"], reverse=True)
        for i in range(min(process_lines, len(sorted_procs))):
            p = sorted_procs[i]
            line = f"{p['pid']:>5} {p['user']:<9} {p['cpu_color']}{p['cpu']:5.1f}{RESET}  {p['mem']:4.1f}  {p['command']}"
            output.append(f"{clear_line()}{line[:self.width-1]}\n")

        output.append(cursor_to(self.height, 1))
        status = f" {BOLD}Iteration: {self.iteration}{RESET} | {self.label} | Press Ctrl-C to stop "
        output.append(f"{REVERSE}{status}{' ' * (self.width - len(status) - 10)}{RESET}")

        return "".join(output)

    def teardown(self):
        print(reset_scroll_region() + cursor_show() + exit_alt_screen(), end="", flush=True)


class WatchMode(DashboardMode):
    """Full-screen clear and redraw, like watch command."""

    def setup(self):
        print(enter_alt_screen() + cursor_hide(), end="", flush=True)

    def update(self):
        self.iteration += 1
        output = [clear_screen(), cursor_home()]

        timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
        output.append(f"{BOLD}Every 0.1s: dashboard watch mode{RESET}    {timestamp}\n\n")
        output.append(f"Load average: {random.uniform(0, 4):.2f} {random.uniform(0, 4):.2f} {random.uniform(0, 4):.2f}\n")
        output.append(f"Tasks: {random.randint(100, 300)} total, {random.randint(1, 5)} running\n")
        output.append(f"Memory: {random.randint(4000, 8000)}M used / 16384M total\n\n")
        output.append(f"{BOLD}{'PID':>7} {'USER':<10} {'%CPU':>6} {'%MEM':>6} {'COMMAND':<30}{RESET}\n")

        for _ in range(min(15, self.height - 10)):
            pid = random.randint(1, 99999)
            user = random.choice(["root", "admin", "www-data", "daemon"])
            cpu = random.uniform(0, 100)
            mem = random.uniform(0, 20)
            cmd = random.choice(["python3", "node", "docker", "iTerm2", "bash", "vim"])
            line_color = FG_RED if cpu > 50 else (FG_YELLOW if cpu > 20 else "")
            output.append(f"{line_color}{pid:>7} {user:<10} {cpu:>6.1f} {mem:>6.1f} {cmd:<30}{RESET}\n")

        return "".join(output)

    def teardown(self):
        print(cursor_show() + exit_alt_screen(), end="", flush=True)


class ProgressMode(DashboardMode):
    """Multiple progress bars updating in place."""

    def __init__(self, label=""):
        super().__init__(label)
        self.bar_count = 20
        self.progress = [random.uniform(0, 1) for _ in range(self.bar_count)]
        self.speeds = [random.uniform(0.01, 0.05) for _ in range(self.bar_count)]
        self.directions = [1] * self.bar_count

    def setup(self):
        print(enter_alt_screen() + cursor_hide() + clear_screen(), end="", flush=True)
        print(cursor_home(), end="")
        print(f"{BOLD}Progress Bars Stress Test{RESET}")
        print(f"Iteration: 0")
        for i in range(self.bar_count):
            print(f"Task {i+1:2}: ")

    def update(self):
        self.iteration += 1
        output = []

        for i in range(self.bar_count):
            self.progress[i] += self.speeds[i] * self.directions[i]
            if self.progress[i] >= 1:
                self.progress[i] = 1
                self.directions[i] = -1
                self.speeds[i] = random.uniform(0.01, 0.05)
            elif self.progress[i] <= 0:
                self.progress[i] = 0
                self.directions[i] = 1
                self.speeds[i] = random.uniform(0.01, 0.05)

        output.append(cursor_to(2, 12))
        output.append(f"{self.iteration}")

        bar_width = min(50, self.width - 15)
        for i in range(self.bar_count):
            output.append(cursor_to(3 + i, 10))
            bar = progress_bar(self.progress[i], bar_width,
                             color_thresholds=[(0.5, FG_YELLOW), (0.8, FG_RED)])
            output.append(f"{bar} {self.progress[i]*100:5.1f}%{clear_to_eol()}")

        return "".join(output)

    def teardown(self):
        print(cursor_show() + exit_alt_screen(), end="", flush=True)


class TableMode(DashboardMode):
    """Fixed header with scrolling body using scroll regions."""

    def __init__(self, label=""):
        super().__init__(label)
        self.header_height = 4
        self.row_id = 0

    def setup(self):
        print(enter_alt_screen() + cursor_hide() + clear_screen(), end="", flush=True)
        print(cursor_home(), end="")
        print(f"{BOLD}Table with Scroll Region - {self.label}{RESET}")
        print(f"{'─' * (self.width - 1)}")
        print(f"{REVERSE}{'ID':>6} {'Timestamp':<20} {'Value':>10} {'Status':<12} {'Message':<30}{RESET}")
        print(f"{'─' * (self.width - 1)}")
        print(set_scroll_region(self.header_height + 1, self.height - 1), end="", flush=True)

    def update(self):
        self.iteration += 1
        self.row_id += 1
        timestamp = time.strftime("%H:%M:%S.") + f"{int(time.time() * 1000) % 1000:03d}"
        value = random.randint(0, 10000)
        status = random.choice(["OK", "WARN", "ERROR", "PENDING"])
        status_color = {"OK": FG_GREEN, "WARN": FG_YELLOW, "ERROR": FG_RED, "PENDING": FG_CYAN}[status]
        messages = ["Processing request", "Data synchronized", "Cache miss", "Connection reset",
                   "Timeout occurred", "Retry scheduled", "Batch complete"]
        message = random.choice(messages)

        output = [cursor_to(self.height - 1, 1)]
        output.append(f"{self.row_id:>6} {timestamp:<20} {value:>10} {status_color}{status:<12}{RESET} {message:<30}\n")
        return "".join(output)

    def teardown(self):
        print(reset_scroll_region() + cursor_show() + exit_alt_screen(), end="", flush=True)


class StatusMode(DashboardMode):
    """Grid of color-coded service status cells."""

    def __init__(self, label=""):
        super().__init__(label)
        self.services = [
            "web-1", "web-2", "web-3", "api-1", "api-2", "db-master", "db-replica",
            "cache-1", "cache-2", "queue", "worker-1", "worker-2", "worker-3",
            "monitor", "logging", "auth", "storage", "cdn", "dns", "lb-1", "lb-2",
            "backup", "cron", "mailer"
        ]
        self.statuses = {s: random.choice(["up", "up", "up", "up", "degraded", "down"])
                        for s in self.services}
        self.last_change = {s: 0 for s in self.services}

    def setup(self):
        print(enter_alt_screen() + cursor_hide() + clear_screen(), end="", flush=True)

    def update(self):
        self.iteration += 1
        output = [cursor_home()]
        output.append(f"{BOLD}Service Status Dashboard{RESET} - Iteration {self.iteration}\n")
        output.append(f"{'─' * (self.width - 1)}\n\n")

        for service in random.sample(self.services, min(3, len(self.services))):
            old = self.statuses[service]
            new = random.choice(["up", "up", "up", "degraded", "down"])
            if old != new:
                self.statuses[service] = new
                self.last_change[service] = self.iteration

        cell_width = 14
        cols = max(1, (self.width - 2) // cell_width)

        for i, service in enumerate(self.services):
            if i > 0 and i % cols == 0:
                output.append("\n\n")

            status = self.statuses[service]
            recently_changed = (self.iteration - self.last_change[service]) < 10

            if status == "up":
                color = f"{BG_GREEN}{FG_BLACK}"
            elif status == "degraded":
                color = f"{BG_YELLOW}{FG_BLACK}"
            else:
                color = f"{BG_RED}{FG_WHITE}"

            if recently_changed and self.iteration % 2 == 0:
                color = f"{BOLD}{color}"

            name = service[:10]
            output.append(f"{color} {name:<10} {RESET} ")

        output.append(f"\n\n{'─' * (self.width - 1)}\n")
        output.append(f"{BG_GREEN}{FG_BLACK} UP {RESET} ")
        output.append(f"{BG_YELLOW}{FG_BLACK} DEGRADED {RESET} ")
        output.append(f"{BG_RED}{FG_WHITE} DOWN {RESET}\n")

        return "".join(output)

    def teardown(self):
        print(cursor_show() + exit_alt_screen(), end="", flush=True)


# =============================================================================
# Dashboard runner
# =============================================================================

DASHBOARD_MODES = {
    "htop": HtopMode,
    "watch": WatchMode,
    "progress": ProgressMode,
    "table": TableMode,
    "status": StatusMode,
}


def run_dashboard(duration, label="", mode_name="htop", fps=30):
    """Run a dashboard mode for the specified duration at target fps."""
    if mode_name not in DASHBOARD_MODES:
        print(f"Unknown dashboard mode: {mode_name}")
        sys.exit(1)

    mode = DASHBOARD_MODES[mode_name](label)
    prefix = f"[{label}] " if label else ""

    # Clamp fps to at least 1 frame per duration
    min_fps = 1.0 / duration if duration > 0 else 1.0
    if fps > 0 and fps < min_fps:
        fps = min_fps

    # fps=0 or frame time < 0.1ms means no throttling
    if fps == 0:
        throttle = False
        frame_time = 0
    else:
        frame_time = 1.0 / fps
        throttle = frame_time >= 0.0001  # 0.1ms threshold

    if throttle:
        print(f"{prefix}Running dashboard mode '{mode_name}' for {duration} seconds @ {fps}fps...")
    else:
        print(f"{prefix}Running dashboard mode '{mode_name}' for {duration} seconds (unthrottled)...")

    mode.setup()
    start = time.time()

    try:
        if throttle:
            while time.time() - start < duration:
                frame_start = time.time()
                output = mode.update()
                print(output, end="", flush=True)
                sleep_time = frame_time - (time.time() - frame_start)
                if sleep_time > 0:
                    time.sleep(sleep_time)
        else:
            # Unthrottled - no sleep calls in hot loop
            while time.time() - start < duration:
                output = mode.update()
                print(output, end="", flush=True)
    except KeyboardInterrupt:
        pass
    finally:
        mode.teardown()
        print(f"{prefix}Dashboard complete: {mode.iteration} iterations")

    return mode.iteration


# =============================================================================
# Terminal output stress test
# =============================================================================

STRESS_MODES = {"normal", "buffer", "clearcodes", "flood"}


def stress_test(duration, label="", modes=None, title_interval_ms=0, speed="normal"):
    """Generate lots of terminal output to stress test rendering."""
    prefix = f"[{label}] " if label else ""
    modes = modes or ["normal"]

    # Flood mode: run 'yes' directly for maximum throughput
    if modes == ["flood"]:
        print(f"{prefix}Running flood mode for {duration} seconds (using 'yes')...")
        proc = None
        try:
            proc = subprocess.Popen(["yes"], stdout=sys.stdout, stderr=subprocess.DEVNULL)
            time.sleep(duration)
            proc.terminate()
            proc.wait()
        except FileNotFoundError:
            print(f"{prefix}Error: 'yes' command not found", file=sys.stderr)
            return 0, None
        except KeyboardInterrupt:
            if proc:
                proc.terminate()
                proc.wait()
        print(f"{prefix}Flood mode complete")
        return 0, None

    title_info = f", titles every {title_interval_ms}ms" if title_interval_ms > 0 else ""
    speed_info = ", slow mode (100ms/iter)" if speed == "slow" else ""
    print(f"{prefix}Running stress test for {duration} seconds (modes: {','.join(modes)}{title_info}{speed_info})...")
    start = time.time()
    iteration = 0

    # Output patterns - tuple of (lambda, is_clear_code)
    all_patterns = [
        (lambda i: "x" * 200, False),
        (lambda i: f"\033[{31 + (i % 7)}m\033[{40 + (i % 7)}mColored text iteration {i}\033[0m", False),
        (lambda i: "漢字テスト中文한글" * 10, False),
        (lambda i: f"Line {i}: " + "日本語ABC中文DEF한글GHI" * 5, False),
        (lambda i: f"LTR start مرحبا بالعالم שלום עולם end LTR {i}", False),
        (lambda i: f"Price: ₪{i} or ${i}.99 - מחיר: {i} شيكل", False),
        (lambda i: "👨‍👩‍👧‍👦🏳️‍🌈👍🏽🇺🇸🎉✨🔥💯" * 5, False),
        (lambda i: "e\u0301a\u0300o\u0302u\u0308n\u0303" * 20, False),
        (lambda i: f"\033[{1 + (i % 20)}C\033[{1 + (i % 5)}A\033[{1 + (i % 5)}B" + ">" * 30, False),
        (lambda i: f"col1\tcol2\tcol3\tcol4\t{i}", False),
        (lambda i: "".join(f"\033[{31 + (j % 7)}m{chr(65 + (j % 26))}" for j in range(80)) + "\033[0m", False),
        (lambda i: f"\033[5mBLINK {i}\033[0m", False),
        (lambda i: f"\033[7;4;3mSTYLE {i}\033[0m", False),
        (lambda i: f"\033[sSaved{i}\033[uRestored{i}", False),
        (lambda i: f"\033[2LInserted{i}\n\033[2MDeleted{i}", True),
        (lambda i: f"\033[5;20rRegion{i}\n\033[r", True),
        (lambda i: f"Erase{i}\033[2K\033[2J", True),
        (lambda i: f"\033[?1049hAlt{i}\n\033[?1049l", True),
        (lambda i: f"\033]8;;https://example.com/{i}\033\\link{i}\033]8;;\033\\", False),
        (lambda i: "┌─┬─┐│├─┼─┤│└─┴─┘" * 8, False),
        (lambda i: "a\u200db\u200cc\uFEFFd" * 30, False),
        (lambda i: ("ABC日本語🎉مرحبا" * 20)[:200], False),
    ]

    normal_patterns = [p[0] for p in all_patterns if not p[1]]
    clearcodes_patterns = [p[0] for p in all_patterns]

    buffer_line = ("BUFFER:" + "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" * 10)[:600]
    bidi_segment = "Text123مرحبا456שלום789עולם012العالم345"
    bidi_line = (bidi_segment * 15)[:600]
    buffer_patterns = [
        lambda i, line=buffer_line: f"{line}{i % 10000:04d}",
        lambda i: "日本語中文한글" * 60,
        lambda i, line=buffer_line: f"\033[32m{line}\033[0m",
        lambda i, line=bidi_line: f"{line}{i % 1000:03d}",
    ]

    pattern_sets = {
        "normal": normal_patterns,
        "clearcodes": clearcodes_patterns,
        "buffer": buffer_patterns,
    }

    # Validate modes
    for mode in modes:
        if mode not in pattern_sets:
            print(f"{prefix}Warning: unknown mode '{mode}', using 'normal'")
            modes = ["normal"]
            break

    current_mode_idx = 0
    current_patterns = pattern_sets[modes[current_mode_idx]]
    mode_start_iteration = 0

    if len(modes) > 1:
        time_slice = duration / len(modes)
        mode_iterations = {}
    else:
        time_slice = duration

    # Title injection via timer thread
    title_count = [0]
    title_timer = [None]
    title_lock = threading.Lock()
    title_interval_sec = title_interval_ms / 1000.0 if title_interval_ms > 0 else 0

    def inject_title():
        with title_lock:
            if title_timer[0] is None:  # Already cancelled
                return
            title_count[0] += 1
            elapsed = time.time() - start
            print(f"\033]0;{prefix}Title {title_count[0]} @ {elapsed:.1f}s\007", flush=True)
            remaining = duration - (time.time() - start)
            if remaining >= 4.0:
                title_timer[0] = threading.Timer(title_interval_sec, inject_title)
                title_timer[0].daemon = True
                title_timer[0].start()
            else:
                title_timer[0] = None

    if title_interval_ms > 0 and duration > 4:
        title_timer[0] = threading.Timer(title_interval_sec, inject_title)
        title_timer[0].daemon = True
        title_timer[0].start()

    while time.time() - start < duration:
        if len(modes) > 1:
            elapsed = time.time() - start
            expected_mode_idx = min(int(elapsed / time_slice), len(modes) - 1)
            if expected_mode_idx != current_mode_idx:
                mode_iterations[modes[current_mode_idx]] = iteration - mode_start_iteration
                mode_start_iteration = iteration
                current_mode_idx = expected_mode_idx
                current_patterns = pattern_sets[modes[current_mode_idx]]
                print(f"{prefix}Switching to mode: {modes[current_mode_idx]} (at {elapsed:.1f}s)")

        pattern = current_patterns[iteration % len(current_patterns)]
        try:
            print(pattern(iteration))
        except UnicodeEncodeError:
            print(f"[encoding error on iteration {iteration}]")
        iteration += 1

        if speed == "slow":
            time.sleep(0.1)

    with title_lock:
        if title_timer[0]:
            title_timer[0].cancel()
            title_timer[0] = None

    if len(modes) > 1:
        mode_iterations[modes[current_mode_idx]] = iteration - mode_start_iteration

    title_info = f", {title_count[0]} title updates" if title_interval_ms > 0 else ""
    print(f"{prefix}Stress test complete: {iteration} iterations{title_info}")
    return iteration, mode_iterations if len(modes) > 1 else None


# =============================================================================
# Sync protocol
# =============================================================================

def wait_for_sync(sync_dir, label):
    """Signal ready and wait for go signal."""
    sync_path = Path(sync_dir)
    ready_file = sync_path / f"ready_{label}"
    go_file = sync_path / "go"

    print(f"[{label}] Signaling ready...")
    ready_file.touch()

    print(f"[{label}] Waiting for go signal...")
    while not go_file.exists():
        time.sleep(0.05)

    print(f"[{label}] Go signal received!")


def write_stats(sync_dir, label, iterations, duration, mode_iterations=None):
    """Write stats to sync_dir for aggregation."""
    if not sync_dir:
        return
    sync_path = Path(sync_dir)
    stats_file = sync_path / f"stats_{label}"
    lines = [f"{iterations}", f"{duration}"]
    if mode_iterations:
        for mode, iters in mode_iterations.items():
            lines.append(f"{mode}:{iters}")
    stats_file.write_text("\n".join(lines) + "\n")


# =============================================================================
# All-modes runner
# =============================================================================

ALL_MODES = ["normal", "buffer", "clearcodes", "htop", "watch", "progress", "table", "status"]


def run_mode_list(modes, duration, label="", title_interval_ms=0, speed="normal", fps=30):
    """Run a list of modes in sequence, time-sliced within a single test run."""
    prefix = f"[{label}] " if label else ""
    num_modes = len(modes)
    time_per_mode = duration / num_modes

    print(f"{prefix}Running {num_modes} modes ({time_per_mode:.1f}s each): {','.join(modes)}")
    total_iterations = 0
    mode_iterations = {}
    start = time.time()

    for i, mode_name in enumerate(modes):
        mode_start = time.time()
        elapsed = mode_start - start
        remaining = duration - elapsed
        mode_duration = min(time_per_mode, remaining)

        if mode_duration <= 0:
            break

        print(f"{prefix}[{elapsed:.1f}s] Switching to mode: {mode_name} (for {mode_duration:.1f}s)")

        if mode_name in DASHBOARD_MODES:
            iters = run_dashboard(mode_duration, label, mode_name, fps)
            mode_iterations[mode_name] = iters
            total_iterations += iters
        else:
            iters, _ = stress_test(mode_duration, label, [mode_name], title_interval_ms, speed)
            mode_iterations[mode_name] = iters
            total_iterations += iters

    elapsed = time.time() - start
    print(f"{prefix}Mode sequence complete: {total_iterations} total iterations in {elapsed:.1f}s")
    return total_iterations, mode_iterations


def run_all_modes(duration, label="", title_interval_ms=0, speed="normal", fps=30):
    """Run all modes in sequence, time-sliced within a single test run."""
    return run_mode_list(ALL_MODES, duration, label, title_interval_ms, speed, fps)


# =============================================================================
# Main
# =============================================================================

def main():
    duration = 10
    label = ""
    sync_dir = None
    mode = None
    title_interval_ms = 0
    speed = "normal"
    fps = 30.0

    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--sync-dir" and i + 1 < len(args):
            sync_dir = args[i + 1]
            i += 2
        elif args[i].startswith("--mode="):
            mode = args[i].split("=", 1)[1]
            i += 1
        elif args[i] == "--title":
            title_interval_ms = 2000
            i += 1
        elif args[i].startswith("--title="):
            title_interval_ms = int(args[i].split("=", 1)[1])
            i += 1
        elif args[i].startswith("--speed="):
            speed = args[i].split("=", 1)[1]
            if speed not in ("normal", "slow"):
                print(f"Warning: invalid --speed value '{speed}', using 'normal'")
                speed = "normal"
            i += 1
        elif args[i].startswith("--fps="):
            fps = float(args[i].split("=", 1)[1])
            if fps < 0:
                print(f"Warning: --fps={fps} must be non-negative, using 30")
                fps = 30
            i += 1
        elif duration == 10 and args[i].isdigit():
            duration = int(args[i])
            i += 1
        elif not label:
            label = args[i]
            i += 1
        else:
            i += 1

    if sync_dir:
        wait_for_sync(sync_dir, label or "unknown")

    # Handle 'all' mode - cycles through all modes in a single run
    if mode == "all":
        iterations, mode_iterations = run_all_modes(duration, label, title_interval_ms, speed, fps)
    elif mode and "," in mode:
        # Comma-separated modes - run each in sequence
        modes = mode.split(",")
        iterations, mode_iterations = run_mode_list(modes, duration, label, title_interval_ms, speed, fps)
    elif mode in DASHBOARD_MODES:
        iterations = run_dashboard(duration, label, mode, fps)
        mode_iterations = None
    else:
        # Single stress mode or default
        modes = [mode] if mode else None
        iterations, mode_iterations = stress_test(duration, label, modes, title_interval_ms, speed)

    write_stats(sync_dir, label or "unknown", iterations, duration, mode_iterations)


if __name__ == "__main__":
    main()
