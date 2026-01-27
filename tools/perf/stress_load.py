#!/usr/bin/env python3
"""
Generate terminal load for stress testing iTerm2.

Usage:
    python3 stress_load.py [duration_seconds] [label] [--sync-dir DIR] [--mode=MODES] [--title] [--speed=SPEED]

This script generates various types of terminal output to exercise
iTerm2's rendering and text processing code paths. It does NOT run
a profiler - use this with run_multi_tab_stress_test.sh for multi-tab
profiled stress testing, or profile_stress_test.py for single-tab use.

With --sync-dir, the script signals readiness and waits for a "go"
signal before starting, allowing synchronized startup across tabs.

Options:
    --title[=MS]  Inject OSC 0 title changes every MS milliseconds (default 2000ms)
    --speed=SPEED Output speed: normal (default) or slow (100ms delay per iteration)

Modes (comma-separated, time-sliced equally across duration):
    simple     - minimal output (80 x's per line), lowest overhead
    normal     - excludes patterns with clear/erase sequences (default)
    clearcodes - all patterns including clear/erase sequences
    buffer     - very long lines (~600 chars), no clears
    flood      - maximum throughput, like 'yes' command (no throttling)
    all        - runs simple, normal, buffer, clearcodes in sequence (mutually exclusive)
"""

import os
import subprocess
import sys
import time
import threading
from pathlib import Path


def stress_test(duration, label="", modes=None, title_interval_ms=0, speed="normal"):
    """Generate lots of terminal output to stress test rendering.

    Args:
        title_interval_ms: If > 0, inject title changes at this interval (milliseconds)
        speed: "normal" (default) or "slow" (100ms delay per iteration)
    """
    prefix = f"[{label}] " if label else ""
    modes = modes or ["normal"]

    # Flood mode: run 'yes' directly for maximum throughput
    if modes == ["flood"]:
        print(f"{prefix}Running flood mode for {duration} seconds (using 'yes')...")
        try:
            proc = subprocess.Popen(["yes"], stdout=sys.stdout, stderr=subprocess.DEVNULL)
            time.sleep(duration)
            proc.terminate()
            proc.wait()
        except KeyboardInterrupt:
            proc.terminate()
            proc.wait()
        print(f"{prefix}Flood mode complete")
        return 0, None  # iteration count not meaningful for flood

    title_info = f", titles every {title_interval_ms}ms" if title_interval_ms > 0 else ""
    speed_info = ", slow mode (100ms/iter)" if speed == "slow" else ""
    print(f"{prefix}Running stress test for {duration} seconds (modes: {','.join(modes)}{title_info}{speed_info})...")
    start = time.time()
    iteration = 0

    # Mix of different output patterns to exercise various code paths
    # Especially targeting StringToScreenChars and related hot paths
    # Patterns marked with # CLEARS are excluded in scrollback/buffer modes
    all_patterns = [
        # Plain ASCII (baseline)
        (lambda i: "x" * 200, False),

        # ANSI escape sequences (SGR attributes)
        (lambda i: f"\033[{31 + (i % 7)}m\033[{40 + (i % 7)}mColored text iteration {i}\033[0m", False),

        # Wide characters (CJK) - exercises width calculation
        (lambda i: "漢字テスト中文한글" * 10, False),

        # Mixed ASCII and wide chars
        (lambda i: f"Line {i}: " + "日本語ABC中文DEF한글GHI" * 5, False),

        # RTL text (Arabic/Hebrew) - triggers bidi processing
        (lambda i: f"LTR start مرحبا بالعالم שלום עולם end LTR {i}", False),

        # Mixed bidi with numbers
        (lambda i: f"Price: ₪{i} or ${i}.99 - מחיר: {i} شيكل", False),

        # Emoji (variable width, variation selectors)
        (lambda i: "👨‍👩‍👧‍👦🏳️‍🌈👍🏽🇺🇸🎉✨🔥💯" * 5, False),

        # Combining characters (diacritics)
        (lambda i: "e\u0301a\u0300o\u0302u\u0308n\u0303" * 20, False),  # éàôüñ as combining

        # Control characters and cursor movement
        (lambda i: f"\033[{1 + (i % 20)}C\033[{1 + (i % 5)}A\033[{1 + (i % 5)}B" + ">" * 30, False),

        # Tab characters (tab stop processing)
        (lambda i: f"col1\tcol2\tcol3\tcol4\t{i}", False),

        # Rapid attribute changes
        (lambda i: "".join(f"\033[{31 + (j % 7)}m{chr(65 + (j % 26))}" for j in range(80)) + "\033[0m", False),

        # Blinking text (SGR 5) to exercise blink handling/cadence
        (lambda i: f"\033[5mBLINK {i}\033[0m", False),

        # Style combos (invert + underline + italic) to stress attribute resolution
        (lambda i: f"\033[7;4;3mSTYLE {i}\033[0m", False),

        # Cursor save/restore to stress cursor state churn
        (lambda i: f"\033[sSaved{i}\033[uRestored{i}", False),

        # Insert/delete lines to exercise linebuffer/grid shifting - CLEARS
        (lambda i: f"\033[2LInserted{i}\n\033[2MDeleted{i}", True),

        # Scroll region set/reset to stress scroll-region logic - CLEARS
        (lambda i: f"\033[5;20rRegion{i}\n\033[r", True),

        # Erase in line/screen to exercise clearing paths - CLEARS
        (lambda i: f"Erase{i}\033[2K\033[2J", True),

        # Alternate screen enter/exit to stress buffer swaps - CLEARS
        (lambda i: f"\033[?1049hAlt{i}\n\033[?1049l", True),

        # OSC 8 hyperlinks to exercise URL parsing paths
        (lambda i: f"\033]8;;https://example.com/{i}\033\\link{i}\033]8;;\033\\", False),

        # Box drawing / special chars
        (lambda i: "┌─┬─┐│├─┼─┤│└─┴─┘" * 8, False),

        # Zero-width joiners and other Unicode specials
        (lambda i: "a\u200db\u200cc\uFEFFd" * 30, False),

        # Long line with mixed content (tests line wrapping with complex chars)
        (lambda i: ("ABC日本語🎉مرحبا" * 20)[:200], False),
    ]

    # Build pattern sets for each mode
    normal_patterns = [p[0] for p in all_patterns if not p[1]]  # excludes clears
    clearcodes_patterns = [p[0] for p in all_patterns]  # all patterns

    # Buffer mode: long lines (~600 chars), pre-generated, no clears
    buffer_line = ("BUFFER:" + "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" * 10)[:600]
    # Bidi line with Arabic/Hebrew interspersed with numbers (taxes bidi hot loop)
    bidi_segment = "Text123مرحبا456שלום789עולם012العالم345"
    bidi_line = (bidi_segment * 15)[:600]
    buffer_patterns = [
        lambda i, line=buffer_line: f"{line}{i % 10000:04d}",
        lambda i: "日本語中文한글" * 60,  # ~600 chars of CJK
        lambda i, line=buffer_line: f"\033[32m{line}\033[0m",  # colored long line
        lambda i, line=bidi_line: f"{line}{i % 1000:03d}",  # bidi with numbers
    ]

    # DEAD CODE: Simple mode is not exposed via the harness (run_multi_tab_stress_test.sh).
    # Preserved for potential future use. Minimal overhead, predictable output.
    simple_patterns = [
        lambda i: "x" * 80,  # Just 80 x's per line, no formatting
        lambda i: f"\033]0;Stress Test {i}\007",  # OSC 0 - set window/icon title
    ]

    pattern_sets = {
        "simple": simple_patterns,
        "normal": normal_patterns,
        "clearcodes": clearcodes_patterns,
        "buffer": buffer_patterns,
    }

    # Handle 'all' mode - expands to all four modes
    if modes == ["all"]:
        modes = ["simple", "normal", "buffer", "clearcodes"]
    elif "all" in modes:
        print(f"{prefix}Warning: 'all' mode is mutually exclusive, ignoring other modes")
        modes = ["simple", "normal", "buffer", "clearcodes"]

    # Validate modes
    for mode in modes:
        if mode not in pattern_sets:
            print(f"{prefix}Warning: unknown mode '{mode}', using 'normal'")
            modes = ["normal"]
            break

    current_mode_idx = 0
    current_patterns = pattern_sets[modes[current_mode_idx]]

    # Time-based mode switching: divide duration equally among modes
    if len(modes) > 1:
        time_slice = duration / len(modes)
        mode_iterations = {mode: 0 for mode in modes}
    else:
        time_slice = duration

    # Title injection via timer thread (avoids per-iteration check overhead)
    title_count = [0]  # Use list for mutable closure
    title_timer = [None]
    title_interval_sec = title_interval_ms / 1000.0 if title_interval_ms > 0 else 0
    title_warning = [None]  # Warning message if titles couldn't be scheduled

    def inject_title():
        title_count[0] += 1
        elapsed = time.time() - start
        # OSC 0 sets both window and icon title
        print(f"\033]0;{prefix}Title {title_count[0]} @ {elapsed:.1f}s\007", flush=True)
        # Schedule next title only if >= 4s remaining (avoid orphaned completions)
        remaining = duration - (time.time() - start)
        if remaining >= 4.0:
            title_timer[0] = threading.Timer(title_interval_sec, inject_title)
            title_timer[0].daemon = True
            title_timer[0].start()

    if title_interval_ms > 0:
        if duration <= 4:
            title_warning[0] = f"Warning: duration ({duration}s) <= 4s, no title updates scheduled"
        else:
            title_timer[0] = threading.Timer(title_interval_sec, inject_title)
            title_timer[0].daemon = True
            title_timer[0].start()

    while time.time() - start < duration:
        # Switch modes based on time slices if multiple modes specified
        if len(modes) > 1:
            elapsed = time.time() - start
            expected_mode_idx = min(int(elapsed / time_slice), len(modes) - 1)
            if expected_mode_idx != current_mode_idx:
                # Record iterations for current mode before switching
                mode_iterations[modes[current_mode_idx]] = iteration - sum(
                    v for k, v in mode_iterations.items() if k != modes[current_mode_idx]
                )
                current_mode_idx = expected_mode_idx
                current_patterns = pattern_sets[modes[current_mode_idx]]
                print(f"{prefix}Switching to mode: {modes[current_mode_idx]} (at {elapsed:.1f}s)")

        pattern = current_patterns[iteration % len(current_patterns)]
        try:
            print(pattern(iteration))
        except UnicodeEncodeError:
            print(f"[encoding error on iteration {iteration}]")
        iteration += 1

        # Throttle output based on speed setting
        if speed == "slow":
            time.sleep(0.1)  # 100ms delay per iteration
        elif iteration % 100 == 0:
            # Small delay to not completely overwhelm (normal mode only)
            time.sleep(0.001)

    # Cancel any pending title timer
    if title_timer[0]:
        title_timer[0].cancel()

    # Calculate final mode's iterations if multi-mode
    if len(modes) > 1:
        mode_iterations[modes[current_mode_idx]] = iteration - sum(
            v for k, v in mode_iterations.items() if k != modes[current_mode_idx]
        )

    # Print results
    title_info = f", {title_count[0]} title updates" if title_interval_ms > 0 else ""
    print(f"{prefix}Stress test complete: {iteration} iterations{title_info}")
    if title_warning[0]:
        print(f"{prefix}{title_warning[0]}")
    return iteration, mode_iterations if len(modes) > 1 else None


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


def write_stats(sync_dir, label, iterations, duration, mode_iterations=None):
    """Write stats to sync_dir for aggregation.

    Stats file format:
        total_iterations
        duration
        mode1:iterations1  (optional, if multi-mode)
        mode2:iterations2
        ...
    """
    if not sync_dir:
        return
    sync_path = Path(sync_dir)
    stats_file = sync_path / f"stats_{label}"
    lines = [f"{iterations}", f"{duration}"]
    if mode_iterations:
        for mode, iters in mode_iterations.items():
            lines.append(f"{mode}:{iters}")
    stats_file.write_text("\n".join(lines) + "\n")


def main():
    # Parse arguments
    duration = 10
    label = ""
    sync_dir = None
    modes = None
    title_interval_ms = 0  # 0 = disabled
    speed = "normal"

    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--sync-dir" and i + 1 < len(args):
            sync_dir = args[i + 1]
            i += 2
        elif args[i].startswith("--mode="):
            modes = args[i].split("=", 1)[1].split(",")
            i += 1
        elif args[i] == "--title":
            title_interval_ms = 2000  # default 2s
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

    iterations, mode_iterations = stress_test(duration, label, modes, title_interval_ms, speed)

    # Write stats for aggregation
    write_stats(sync_dir, label or "unknown", iterations, duration, mode_iterations)


if __name__ == "__main__":
    main()
