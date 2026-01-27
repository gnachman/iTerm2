#!/usr/bin/env python3
"""
Dashboard-style load generator for stress testing iTerm2.

Generates htop-style in-place updating displays that stress cursor positioning,
scroll regions, partial redraws, and color handling.

Usage:
    python3 load_dashboard.py [duration_seconds] [label] [--sync-dir DIR] [--mode=MODE]

Modes:
    htop      - CPU meters + scrolling process list (default)
    watch     - Full-screen clear + redraw every 100ms
    progress  - 20 progress bars updating in place
    table     - Fixed header + scroll region body
    status    - Grid of color-coded service status cells

Uses the same sync protocol as stress_load.py for coordinated startup.
"""

import os
import random
import shutil
import sys
import time
from pathlib import Path


# ANSI escape sequences
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

# Cursor control
def cursor_home():
    return f"{CSI}H"

def cursor_to(row, col):
    return f"{CSI}{row};{col}H"

def cursor_up(n=1):
    return f"{CSI}{n}A"

def cursor_down(n=1):
    return f"{CSI}{n}B"

def cursor_save():
    return f"{ESC}7"

def cursor_restore():
    return f"{ESC}8"

def cursor_hide():
    return f"{CSI}?25l"

def cursor_show():
    return f"{CSI}?25h"

# Screen control
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

def scroll_up(n=1):
    return f"{CSI}{n}S"

def scroll_down(n=1):
    return f"{CSI}{n}T"

def enter_alt_screen():
    return f"{CSI}?1049h"

def exit_alt_screen():
    return f"{CSI}?1049l"


def get_terminal_size():
    """Get terminal dimensions."""
    size = shutil.get_terminal_size(fallback=(80, 24))
    return size.columns, size.lines


def progress_bar(value, width, filled_char="█", empty_char="░", color_thresholds=None):
    """Generate a progress bar string.

    Args:
        value: 0.0 to 1.0
        width: Total width including brackets
        filled_char: Character for filled portion
        empty_char: Character for empty portion
        color_thresholds: List of (threshold, color) tuples, e.g. [(0.5, FG_YELLOW), (0.8, FG_RED)]
    """
    inner_width = width - 2  # Account for [ ]
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
        "python3 stress_load.py",
        "/usr/bin/sample iTerm2",
        "iTerm2 --server",
        "/System/Library/Metal",
        "WindowServer",
        "mds_stores",
        "kernel_task",
        "launchd",
        "sshd: admin",
        "vim /etc/hosts",
        "docker compose up",
        "node server.js",
        "postgres: writer",
    ]
    command = random.choice(commands)

    # Color based on CPU usage
    if cpu > 80:
        cpu_color = FG_RED
    elif cpu > 50:
        cpu_color = FG_YELLOW
    else:
        cpu_color = FG_GREEN

    return {
        "pid": pid,
        "user": user,
        "cpu": cpu,
        "mem": mem,
        "command": command,
        "cpu_color": cpu_color,
    }


class DashboardMode:
    """Base class for dashboard modes."""

    def __init__(self, label=""):
        self.label = label
        self.iteration = 0
        self.width, self.height = get_terminal_size()

    def setup(self):
        """Called once at start."""
        pass

    def update(self):
        """Called each frame. Returns string to print."""
        self.iteration += 1
        return ""

    def teardown(self):
        """Called at end."""
        pass


class HtopMode(DashboardMode):
    """Htop-style display with CPU meters and process list."""

    def __init__(self, label=""):
        super().__init__(label)
        self.cpu_count = min(8, (self.height - 10) // 2)  # Simulate 8 CPUs max
        self.cpu_values = [random.uniform(0, 1) for _ in range(self.cpu_count)]
        self.mem_value = random.uniform(0.3, 0.7)
        self.swap_value = random.uniform(0, 0.3)
        self.processes = [generate_fake_process() for _ in range(50)]
        self.process_scroll = 0
        self.header_lines = 3 + self.cpu_count + 2  # Title + CPUs + mem/swap + separator

    def setup(self):
        print(enter_alt_screen(), end="", flush=True)
        print(cursor_hide(), end="", flush=True)
        print(clear_screen(), end="", flush=True)

    def update(self):
        self.iteration += 1
        output = []
        output.append(cursor_home())

        # Update CPU values with some variation
        for i in range(self.cpu_count):
            delta = random.uniform(-0.1, 0.1)
            self.cpu_values[i] = max(0, min(1, self.cpu_values[i] + delta))

        # Memory fluctuates slightly
        self.mem_value = max(0.1, min(0.95, self.mem_value + random.uniform(-0.02, 0.02)))
        self.swap_value = max(0, min(0.5, self.swap_value + random.uniform(-0.01, 0.01)))

        # Header
        bar_width = min(40, self.width - 20)

        # CPU meters
        for i in range(self.cpu_count):
            bar = progress_bar(self.cpu_values[i], bar_width,
                             color_thresholds=[(0.5, FG_YELLOW), (0.8, FG_RED)])
            pct = self.cpu_values[i] * 100
            output.append(f"{clear_line()}CPU{i}: {bar} {pct:5.1f}%\n")

        # Memory and swap
        mem_bar = progress_bar(self.mem_value, bar_width, color_thresholds=[(0.7, FG_YELLOW), (0.9, FG_RED)])
        swap_bar = progress_bar(self.swap_value, bar_width, color_thresholds=[(0.5, FG_YELLOW), (0.8, FG_RED)])
        output.append(f"{clear_line()}Mem: {mem_bar} {self.mem_value * 100:5.1f}%\n")
        output.append(f"{clear_line()}Swp: {swap_bar} {self.swap_value * 100:5.1f}%\n")

        # Separator
        output.append(f"{clear_line()}{BOLD}{REVERSE} PID    USER      CPU%  MEM%  COMMAND{' ' * (self.width - 45)}{RESET}\n")

        # Process list - use scroll region
        process_lines = self.height - self.header_lines - 2

        # Update some random processes
        for _ in range(5):
            idx = random.randint(0, len(self.processes) - 1)
            self.processes[idx] = generate_fake_process()

        # Sort by CPU (descending)
        sorted_procs = sorted(self.processes, key=lambda p: p["cpu"], reverse=True)

        # Display processes
        for i in range(min(process_lines, len(sorted_procs))):
            p = sorted_procs[i]
            line = f"{p['pid']:>5} {p['user']:<9} {p['cpu_color']}{p['cpu']:5.1f}{RESET}  {p['mem']:4.1f}  {p['command']}"
            line = line[:self.width - 1]  # Truncate to screen width
            output.append(f"{clear_line()}{line}\n")

        # Status bar at bottom
        output.append(cursor_to(self.height, 1))
        status = f" {BOLD}Iteration: {self.iteration}{RESET} | {self.label} | Press Ctrl-C to stop "
        output.append(f"{REVERSE}{status}{' ' * (self.width - len(status) - 10)}{RESET}")

        return "".join(output)

    def teardown(self):
        print(reset_scroll_region(), end="", flush=True)
        print(cursor_show(), end="", flush=True)
        print(exit_alt_screen(), end="", flush=True)


class WatchMode(DashboardMode):
    """Full-screen clear and redraw, like watch command."""

    def setup(self):
        print(enter_alt_screen(), end="", flush=True)
        print(cursor_hide(), end="", flush=True)

    def update(self):
        self.iteration += 1
        output = []
        output.append(clear_screen())
        output.append(cursor_home())

        # Header
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
        output.append(f"{BOLD}Every 0.1s: dashboard watch mode{RESET}    {timestamp}\n\n")

        # System stats (simulated)
        output.append(f"Load average: {random.uniform(0, 4):.2f} {random.uniform(0, 4):.2f} {random.uniform(0, 4):.2f}\n")
        output.append(f"Tasks: {random.randint(100, 300)} total, {random.randint(1, 5)} running\n")
        output.append(f"Memory: {random.randint(4000, 8000)}M used / 16384M total\n\n")

        # Process table
        output.append(f"{BOLD}{'PID':>7} {'USER':<10} {'%CPU':>6} {'%MEM':>6} {'COMMAND':<30}{RESET}\n")

        for _ in range(min(15, self.height - 10)):
            pid = random.randint(1, 99999)
            user = random.choice(["root", "admin", "www-data", "daemon"])
            cpu = random.uniform(0, 100)
            mem = random.uniform(0, 20)
            cmd = random.choice(["python3", "node", "docker", "iTerm2", "bash", "vim"])

            if cpu > 50:
                line_color = FG_RED
            elif cpu > 20:
                line_color = FG_YELLOW
            else:
                line_color = ""

            output.append(f"{line_color}{pid:>7} {user:<10} {cpu:>6.1f} {mem:>6.1f} {cmd:<30}{RESET}\n")

        return "".join(output)

    def teardown(self):
        print(cursor_show(), end="", flush=True)
        print(exit_alt_screen(), end="", flush=True)


class ProgressMode(DashboardMode):
    """Multiple progress bars updating in place."""

    def __init__(self, label=""):
        super().__init__(label)
        self.bar_count = 20
        self.progress = [random.uniform(0, 1) for _ in range(self.bar_count)]
        self.speeds = [random.uniform(0.01, 0.05) for _ in range(self.bar_count)]
        self.directions = [1] * self.bar_count  # 1 = forward, -1 = backward

    def setup(self):
        print(enter_alt_screen(), end="", flush=True)
        print(cursor_hide(), end="", flush=True)
        print(clear_screen(), end="", flush=True)

        # Print static labels
        print(cursor_home(), end="")
        print(f"{BOLD}Progress Bars Stress Test{RESET}")
        print(f"Iteration: 0")
        for i in range(self.bar_count):
            print(f"Task {i+1:2}: ")

    def update(self):
        self.iteration += 1
        output = []

        # Update progress values (bounce back and forth)
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

        # Update iteration counter
        output.append(cursor_to(2, 12))
        output.append(f"{self.iteration}")

        # Update each bar
        bar_width = min(50, self.width - 15)
        for i in range(self.bar_count):
            output.append(cursor_to(3 + i, 10))
            bar = progress_bar(self.progress[i], bar_width,
                             color_thresholds=[(0.5, FG_YELLOW), (0.8, FG_RED)])
            output.append(f"{bar} {self.progress[i]*100:5.1f}%{clear_to_eol()}")

        return "".join(output)

    def teardown(self):
        print(cursor_show(), end="", flush=True)
        print(exit_alt_screen(), end="", flush=True)


class TableMode(DashboardMode):
    """Fixed header with scrolling body using scroll regions."""

    def __init__(self, label=""):
        super().__init__(label)
        self.header_height = 4
        self.data_rows = []
        self.row_id = 0

    def setup(self):
        print(enter_alt_screen(), end="", flush=True)
        print(cursor_hide(), end="", flush=True)
        print(clear_screen(), end="", flush=True)

        # Draw fixed header
        print(cursor_home(), end="")
        print(f"{BOLD}Table with Scroll Region - {self.label}{RESET}")
        print(f"{'─' * (self.width - 1)}")
        print(f"{REVERSE}{'ID':>6} {'Timestamp':<20} {'Value':>10} {'Status':<12} {'Message':<30}{RESET}")
        print(f"{'─' * (self.width - 1)}")

        # Set scroll region for data area only
        print(set_scroll_region(self.header_height + 1, self.height - 1), end="", flush=True)

    def update(self):
        self.iteration += 1
        output = []

        # Add new row
        self.row_id += 1
        timestamp = time.strftime("%H:%M:%S.") + f"{int(time.time() * 1000) % 1000:03d}"
        value = random.randint(0, 10000)
        status = random.choice(["OK", "WARN", "ERROR", "PENDING"])
        status_color = {"OK": FG_GREEN, "WARN": FG_YELLOW, "ERROR": FG_RED, "PENDING": FG_CYAN}[status]
        messages = ["Processing request", "Data synchronized", "Cache miss", "Connection reset",
                   "Timeout occurred", "Retry scheduled", "Batch complete"]
        message = random.choice(messages)

        # Move to bottom of scroll region and add new line
        output.append(cursor_to(self.height - 1, 1))
        output.append(f"{self.row_id:>6} {timestamp:<20} {value:>10} {status_color}{status:<12}{RESET} {message:<30}\n")

        return "".join(output)

    def teardown(self):
        print(reset_scroll_region(), end="", flush=True)
        print(cursor_show(), end="", flush=True)
        print(exit_alt_screen(), end="", flush=True)


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
        print(enter_alt_screen(), end="", flush=True)
        print(cursor_hide(), end="", flush=True)
        print(clear_screen(), end="", flush=True)

    def update(self):
        self.iteration += 1
        output = []
        output.append(cursor_home())

        # Header
        output.append(f"{BOLD}Service Status Dashboard{RESET} - Iteration {self.iteration}\n")
        output.append(f"{'─' * (self.width - 1)}\n\n")

        # Randomly change some statuses
        for service in random.sample(self.services, min(3, len(self.services))):
            old = self.statuses[service]
            new = random.choice(["up", "up", "up", "degraded", "down"])
            if old != new:
                self.statuses[service] = new
                self.last_change[service] = self.iteration

        # Display as grid
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

            # Blink effect for recently changed
            if recently_changed and self.iteration % 2 == 0:
                color = f"{BOLD}{color}"

            # Format cell
            name = service[:10]
            cell = f" {name:<10} "
            output.append(f"{color}{cell}{RESET} ")

        # Legend
        output.append(f"\n\n{'─' * (self.width - 1)}\n")
        output.append(f"{BG_GREEN}{FG_BLACK} UP {RESET} ")
        output.append(f"{BG_YELLOW}{FG_BLACK} DEGRADED {RESET} ")
        output.append(f"{BG_RED}{FG_WHITE} DOWN {RESET}\n")

        return "".join(output)

    def teardown(self):
        print(cursor_show(), end="", flush=True)
        print(exit_alt_screen(), end="", flush=True)


def wait_for_sync(sync_dir, label):
    """Signal ready and wait for go signal."""
    sync_path = Path(sync_dir)
    ready_file = sync_path / f"ready_{label}"
    go_file = sync_path / "go"

    # Signal that we're ready
    print(f"[{label}] Signaling ready...")
    ready_file.touch()

    # Wait for go signal
    print(f"[{label}] Waiting for go signal...")
    while not go_file.exists():
        time.sleep(0.05)

    print(f"[{label}] Go signal received!")


def write_stats(sync_dir, label, iterations, duration):
    """Write stats to sync_dir for aggregation."""
    if not sync_dir:
        return
    sync_path = Path(sync_dir)
    stats_file = sync_path / f"stats_{label}"
    stats_file.write_text(f"{iterations}\n{duration}\n")


def run_dashboard(duration, label="", mode_name="htop"):
    """Run the dashboard for the specified duration."""
    modes = {
        "htop": HtopMode,
        "watch": WatchMode,
        "progress": ProgressMode,
        "table": TableMode,
        "status": StatusMode,
    }

    if mode_name not in modes:
        print(f"Unknown mode: {mode_name}. Available: {', '.join(modes.keys())}")
        sys.exit(1)

    mode = modes[mode_name](label)

    print(f"[{label}] Running dashboard mode '{mode_name}' for {duration} seconds...")

    mode.setup()
    start = time.time()
    target_fps = 30
    frame_time = 1.0 / target_fps

    try:
        while time.time() - start < duration:
            frame_start = time.time()

            output = mode.update()
            print(output, end="", flush=True)

            # Maintain target frame rate
            elapsed = time.time() - frame_start
            sleep_time = frame_time - elapsed
            if sleep_time > 0:
                time.sleep(sleep_time)
    except KeyboardInterrupt:
        pass
    finally:
        mode.teardown()
        print(f"[{label}] Dashboard complete: {mode.iteration} iterations")

    return mode.iteration


def main():
    # Parse arguments
    duration = 10
    label = ""
    sync_dir = None
    mode_name = "htop"

    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--sync-dir" and i + 1 < len(args):
            sync_dir = args[i + 1]
            i += 2
        elif args[i].startswith("--mode="):
            mode_name = args[i].split("=", 1)[1]
            i += 1
        elif duration == 10 and args[i].isdigit():
            duration = int(args[i])
            i += 1
        elif not label:
            label = args[i]
            i += 1
        else:
            i += 1

    # If sync mode, wait for coordination
    if sync_dir:
        wait_for_sync(sync_dir, label or "unknown")

    iterations = run_dashboard(duration, label, mode_name)

    # Write stats for aggregation
    write_stats(sync_dir, label or "unknown", iterations, duration)


if __name__ == "__main__":
    main()
