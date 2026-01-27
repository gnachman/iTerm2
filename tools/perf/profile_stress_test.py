#!/usr/bin/env python3
"""
Stress test and profile iTerm2 hot paths.

Usage:
    python3 profile_stress_test.py [output_prefix]

This script:
1. Finds the iTerm2 process
2. Starts a 15-second sample profiler in the background
3. Runs a 10-second stress test generating terminal output
4. Waits for profiler to complete
5. Summarizes results showing preference lookup frequency
"""

import subprocess
import sys
import time
import os
import re
from pathlib import Path

def find_iterm_pid():
    """Find the PID of the first iTerm2 process."""
    result = subprocess.run(
        ["ps", "-axo", "pid,comm"],
        capture_output=True,
        text=True
    )
    for line in result.stdout.strip().split('\n'):
        if line.strip().endswith('/iTerm2'):
            return line.split()[0]

    print("Error: No iTerm2 process found")
    sys.exit(1)

def start_profiler(pid, duration, output_file):
    """Start the sample profiler in the background."""
    print(f"Starting profiler for {duration} seconds (PID: {pid})...")
    proc = subprocess.Popen(
        ["sample", pid, str(duration), "-f", output_file],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    return proc

def stress_test(duration):
    """Generate lots of terminal output to stress test rendering."""
    print(f"Running stress test for {duration} seconds...")
    start = time.time()
    iteration = 0

    # Mix of different output patterns to exercise various code paths
    # Especially targeting StringToScreenChars and related hot paths
    patterns = [
        # Plain ASCII (baseline)
        lambda i: "x" * 200,

        # ANSI escape sequences (SGR attributes)
        lambda i: f"\033[{31 + (i % 7)}m\033[{40 + (i % 7)}mColored text iteration {i}\033[0m",

        # Wide characters (CJK) - exercises width calculation
        lambda i: "漢字テスト中文한글" * 10,

        # Mixed ASCII and wide chars
        lambda i: f"Line {i}: " + "日本語ABC中文DEF한글GHI" * 5,

        # RTL text (Arabic/Hebrew) - triggers bidi processing
        lambda i: f"LTR start مرحبا بالعالم שלום עולם end LTR {i}",

        # Mixed bidi with numbers
        lambda i: f"Price: ₪{i} or ${i}.99 - מחיר: {i} شيكل",

        # Emoji (variable width, variation selectors)
        lambda i: "👨‍👩‍👧‍👦🏳️‍🌈👍🏽🇺🇸🎉✨🔥💯" * 5,

        # Combining characters (diacritics)
        lambda i: "e\u0301a\u0300o\u0302u\u0308n\u0303" * 20,  # éàôüñ as combining

        # Control characters and cursor movement
        lambda i: f"\033[{1 + (i % 20)}C\033[{1 + (i % 5)}A\033[{1 + (i % 5)}B" + ">" * 30,

        # Tab characters (tab stop processing)
        lambda i: f"col1\tcol2\tcol3\tcol4\t{i}",

        # Rapid attribute changes
        lambda i: "".join(f"\033[{31 + (j % 7)}m{chr(65 + (j % 26))}" for j in range(80)) + "\033[0m",

        # Box drawing / special chars
        lambda i: "┌─┬─┐│├─┼─┤│└─┴─┘" * 8,

        # Zero-width joiners and other Unicode specials
        lambda i: "a\u200db\u200cc\uFEFFd" * 30,

        # Long line with mixed content (tests line wrapping with complex chars)
        lambda i: ("ABC日本語🎉مرحبا" * 20)[:200],
    ]

    while time.time() - start < duration:
        pattern = patterns[iteration % len(patterns)]
        try:
            print(pattern(iteration))
        except UnicodeEncodeError:
            print(f"[encoding error on iteration {iteration}]")
        iteration += 1
        # Small delay to not completely overwhelm
        if iteration % 100 == 0:
            time.sleep(0.001)

    print(f"\nStress test complete: {iteration} iterations")
    return iteration

def analyze_profile(output_file):
    """Analyze the profile output for hotspots and inefficiencies."""
    print(f"\nAnalyzing profile: {output_file}")

    if not os.path.exists(output_file):
        print("Error: Profile output file not found")
        return

    with open(output_file, 'r') as f:
        content = f.read()

    # Count occurrences of key patterns.
    patterns = {
        "boolForKey": r'\[iTermPreferences boolForKey:\]',
        "intForKey": r'\[iTermPreferences intForKey:\]',
        "objectForKey": r'\[iTermPreferences objectForKey:\]',
        "updateConfigurationFields": r'updateConfigurationFields',
        "NSUserDefaults": r'NSUserDefaults',
        "@synchronized": r'@synchronized',
        "os_unfair_lock": r'os_unfair_lock',
        # StringToScreenChars and text processing
        "StringToScreenChars": r'StringToScreenChars',
        "ScreenCharArray": r'ScreenCharArray',
        "bidi/Bidi": r'[Bb]idi',
        "VT100Terminal": r'VT100Terminal',
        "executeToken": r'executeToken',
        # Metal rendering
        "Metal": r'Metal|metal|MTL|CAMetalLayer',
        "iTermTextRenderer": r'iTermTextRenderer',
    }

    # Broader categories for spotting redundant work or churn.
    categories = {
        "Allocations": r'\b(malloc|calloc|realloc|free|operator new|operator delete)\b',
        "ObjC retain/release": r'objc_(retain|release|autoreleaseReturnValue|retainAutoreleasedReturnValue)',
        "Autorelease pools": r'NSAutoreleasePool|autoreleasepool',
        "Strings/Unicode": r'NSString|CFString|StringToScreenChars|ScreenCharArray',
        "CoreText": r'CTLine|CTRun|CTFont|CoreText',
        "CoreGraphics": r'CGContext|CGColor|CGPath|CGImage|CoreGraphics',
        "AppKit geometry": r'NSRect|NSMakeRect|convertRect|bounds|frame',
        "Locks/dispatch": r'os_unfair_lock|pthread_mutex|dispatch_semaphore|@synchronized',
        "Terminal parsing": r'VT100Parser|VT100Terminal|VT100Screen|executeToken',
        "Rendering": r'iTermTextRenderer|Metal|metal|MTL|CAMetalLayer',
        "Process/cache": r'iTermProcessCache|TaskNotifier|deepestForegroundJob',
    }

    print("\n" + "=" * 60)
    print("Profile Summary")
    print("=" * 60)

    for name, pattern in patterns.items():
        count = len(re.findall(pattern, content))
        print(f"  {name}: {count} occurrences")

    print("=" * 60)
    print("\n" + "=" * 60)
    print("Category Summary")
    print("=" * 60)
    for name, pattern in categories.items():
        count = len(re.findall(pattern, content))
        print(f"  {name}: {count} occurrences")
    print("=" * 60)

    # Extract top iTerm2 symbols from the call graph.
    symbol_pattern = re.compile(r'^\s*[+!:|]*\s*(\d+)\s+(.+?)\s+\(in iTerm2\)')
    counts = {}
    for line in content.splitlines():
        match = symbol_pattern.match(line)
        if not match:
            continue
        count = int(match.group(1))
        symbol = match.group(2).strip()
        if count > counts.get(symbol, 0):
            counts[symbol] = count

    if counts:
        print("\n" + "=" * 60)
        print("Top iTerm2 Symbols (by sample count)")
        print("=" * 60)
        for symbol, count in sorted(counts.items(), key=lambda item: item[1], reverse=True)[:15]:
            print(f"  {count}  {symbol}")
        print("=" * 60)

    print(f"\nFull profile saved to: {output_file}")

def main():
    prefix = sys.argv[1] if len(sys.argv) > 1 else "iterm_profile"
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    output_file = f"/tmp/{prefix}_{timestamp}.txt"

    pid = find_iterm_pid()
    print(f"Found iTerm2 PID: {pid}")

    # Start profiler (15 seconds)
    profiler = start_profiler(pid, 15, output_file)

    # Give profiler a moment to attach
    time.sleep(0.5)

    # Run stress test (10 seconds)
    iterations = stress_test(10)

    # Wait for profiler to complete
    print("\nWaiting for profiler to complete...")
    profiler.wait()

    # Analyze results
    analyze_profile(output_file)

    return output_file

if __name__ == "__main__":
    main()
