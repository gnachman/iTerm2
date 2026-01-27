#!/usr/bin/env python3
"""
Analyze self-time profiling output from iterm_self_time.d

Parses DTrace output and:
- Filters out non-actionable system symbols (objc_msgSend, malloc, etc.)
- Groups by iTerm2 code vs system code
- Calculates percentages
- Provides actionable summary

Usage:
    sudo dtrace -p PID -s iterm_self_time.d 30 | python3 analyze_self_time.py
    # or
    python3 analyze_self_time.py < dtrace_output.txt
"""

import sys
import re
from collections import defaultdict
from typing import Dict, List, Tuple

# Symbols to filter from "actionable" list
# These are runtime/system overhead, not application code
SYSTEM_SYMBOLS = {
    # Objective-C runtime
    'objc_msgSend', 'objc_msgSendSuper', 'objc_msgSend_stret',
    'objc_msgSendSuper2', 'objc_msgSend_uncached',
    'objc_retain', 'objc_release', 'objc_autorelease',
    'objc_retainAutoreleasedReturnValue', 'objc_autoreleaseReturnValue',
    'objc_storeStrong', 'objc_destroyWeak', 'objc_loadWeakRetained',
    'objc_alloc', 'objc_alloc_init', 'objc_opt_new',
    '_objc_rootAllocWithZone', '_objc_rootDealloc',

    # Memory allocation
    'malloc', 'free', 'calloc', 'realloc', 'malloc_zone_malloc',
    'malloc_zone_free', 'malloc_zone_realloc', 'malloc_zone_calloc',
    'nanov2_malloc', 'nanov2_free', 'szone_malloc', 'szone_free',

    # Memory operations
    'memmove', 'memcpy', 'memset', 'bzero', '__bzero',
    'memcmp', 'strlen', 'strcmp', 'strncmp',

    # libdispatch
    '_dispatch_lane_invoke', '_dispatch_worker_thread2',
    '_dispatch_queue_override_invoke', '_dispatch_call_block_and_release',
    '_dispatch_workloop_worker_thread', '_dispatch_continuation_pop',
    '_dispatch_client_callout', '_dispatch_sync_f_slow',

    # Thread management
    'start_wqthread', 'thread_start', '_pthread_wqthread',
    '__psynch_cvwait', '__psynch_mutexwait', '__semwait_signal',
    'pthread_mutex_lock', 'pthread_mutex_unlock',

    # System calls / kernel
    'mach_msg_trap', 'mach_msg', '__ulock_wait', '__ulock_wake',
    'kevent_qos', 'kevent_id', '__select', '__pselect',

    # CoreFoundation / Foundation internals
    'CFRelease', 'CFRetain', '_CFRelease', '_CFRetain',
    'CFArrayGetCount', 'CFDictionaryGetValue',

    # Other system
    'dyld_stub_binder', '_dyld_start', 'ImageLoaderMachO::*',
}

# Markers that indicate iTerm2/user code (case-insensitive prefix match)
ITERM_MARKERS = [
    'iterm', 'pty', 'vt100', 'metal', 'terminal',
    'screen', 'session', 'tab', 'window', 'profile',
    'conductor', 'token', 'fairness', 'scheduler',
]


def is_system_symbol(symbol: str) -> bool:
    """Check if a symbol is a non-actionable system symbol."""
    # Check exact matches
    if symbol in SYSTEM_SYMBOLS:
        return True

    # Check prefix patterns (runtime/kernel symbols only, not framework prefixes)
    # NS/CF prefixes removed - those are now handled by module-based classification
    system_prefixes = [
        'objc_', '_objc_', 'malloc_', 'szone_', 'nanov2_',
        '_dispatch_', '__pthread_', '_pthread_', 'pthread_',
        'mach_', '__mach_', 'dyld_', '_dyld_',
        '__ulock_', '__psynch_', '__semwait_',
    ]
    for prefix in system_prefixes:
        if symbol.startswith(prefix):
            return True

    return False


def is_iterm_symbol(symbol: str) -> bool:
    """Check if a symbol is iTerm2 application code."""
    symbol_lower = symbol.lower()
    for marker in ITERM_MARKERS:
        if marker in symbol_lower:
            return True
    return False


def normalize_module(module: str) -> str:
    """Normalize module name to handle path and architecture variations.

    DTrace may report modules as:
      - "iTerm2"
      - "iTerm2.app/Contents/MacOS/iTerm2"
      - "iTerm2 (x86_64)"
    """
    # Strip path components
    module = module.split('/')[-1]
    # Strip architecture suffix like " (x86_64)"
    if ' (' in module:
        module = module.split(' (')[0]
    return module


def is_iterm2_module(module: str) -> bool:
    """Check if a module is the iTerm2 binary."""
    return normalize_module(module) == 'iTerm2'


# Known system frameworks/libraries (module names after normalization)
SYSTEM_MODULES = {
    'CoreFoundation', 'Foundation', 'AppKit', 'CoreGraphics',
    'CoreText', 'QuartzCore', 'Metal', 'MetalPerformanceShaders',
    'IOKit', 'Security', 'SystemConfiguration',
}


def is_system_module(module: str) -> bool:
    """Check if a module is a known system library/framework.

    Assumes module is already normalized.
    """
    if module.startswith('lib'):
        return True
    if module in SYSTEM_MODULES:
        return True
    return False


def parse_dtrace_output(lines: List[str]) -> Tuple[Dict[str, int], Dict[str, int], int]:
    """Parse DTrace output and return self-time counts, iTerm2-attributed counts, and unattributed stack samples."""
    self_time_counts: Dict[str, int] = defaultdict(int)
    iterm_attributed: Dict[str, int] = defaultdict(int)
    unattributed_stacks: int = 0
    current_section = None

    # Regex to match DTrace stack frame output
    # Format: "  iTerm2`symbolname+0x123" or "  iTerm2`symbolname+123"
    # or "  libsystem_malloc.dylib`malloc+0x45"
    # Note: Objective-C symbols can have spaces, e.g. "-[Foo bar:baz:]"
    # Offset can be hex (+0x...) or decimal (+...) or absent
    frame_pattern = re.compile(r'^\s+([^`]+)`(.+?)(?:\+(?:0x)?[0-9a-fA-F]+)?$')
    count_pattern = re.compile(r'^\s+(\d+)$')

    current_frames = []

    for line in lines:
        line = line.rstrip()

        # Track sections using markers
        if line == '===SELF_TIME===':
            current_section = 'self_time'
            current_frames = []
            continue
        elif line == '===END_SELF_TIME===':
            current_section = None
            current_frames = []
            continue
        elif line == '===STACKS===':
            current_section = 'stacks'
            current_frames = []
            continue
        elif line == '===END_STACKS===':
            current_section = None
            current_frames = []
            continue

        if current_section not in ('self_time', 'stacks'):
            continue

        # Match frame lines
        frame_match = frame_pattern.match(line)
        if frame_match:
            module = normalize_module(frame_match.group(1))
            symbol = frame_match.group(2)
            current_frames.append((module, symbol))
            continue

        # Match count lines (single number on a line)
        count_match = count_pattern.match(line)
        if count_match and current_frames:
            count = int(count_match.group(1))

            if current_section == 'self_time':
                # For self-time, take the leaf frame (first in DTrace output)
                module, symbol = current_frames[0]
                key = f"{module}:{symbol}"
                self_time_counts[key] += count

            elif current_section == 'stacks':
                # For stacks, find the iTerm2 frame closest to leaf and attribute to it.
                # DTrace prints leaf first, so first iTerm2 match is closest to leaf.
                attributed = False
                for module, symbol in current_frames:
                    if is_iterm2_module(module) and 'DYLD-STUB' not in symbol:
                        iterm_attributed[symbol] += count
                        attributed = True
                        break
                if not attributed:
                    unattributed_stacks += count

            current_frames = []
            continue

        # Empty line resets frame accumulator
        if not line.strip():
            current_frames = []

    return self_time_counts, iterm_attributed, unattributed_stacks


def analyze_and_report(self_time_counts: Dict[str, int], iterm_attributed: Dict[str, int], unattributed_stacks: int) -> None:
    """Analyze counts and print actionable report."""
    if not self_time_counts and not iterm_attributed:
        print("No self-time data found in input.")
        print("Make sure the input contains DTrace output from iterm_self_time.d")
        return

    total_samples = sum(self_time_counts.values())

    # Categorize symbols
    # Keys are "module:symbol" format
    iterm_symbols: List[Tuple[str, int]] = []
    system_symbols: List[Tuple[str, int]] = []
    other_symbols: List[Tuple[str, int]] = []

    for key, count in self_time_counts.items():
        # Parse "module:symbol" format
        if ':' in key:
            module, symbol = key.split(':', 1)
        else:
            module, symbol = '', key

        # Categorize by module first (most reliable)
        if is_iterm2_module(module):
            # iTerm2 module, but filter out DYLD stubs which are system calls
            if 'DYLD-STUB' in symbol:
                system_symbols.append((symbol, count))
            else:
                iterm_symbols.append((symbol, count))
        elif is_system_module(module):
            # Known system module
            system_symbols.append((symbol, count))
        elif is_system_symbol(symbol):
            # Unknown module but symbol looks like system code
            system_symbols.append((symbol, count))
        elif is_iterm_symbol(symbol):
            # Unknown module but symbol looks like iTerm2 code
            iterm_symbols.append((symbol, count))
        else:
            other_symbols.append((symbol, count))

    # Sort by count descending
    iterm_symbols.sort(key=lambda x: x[1], reverse=True)
    system_symbols.sort(key=lambda x: x[1], reverse=True)
    other_symbols.sort(key=lambda x: x[1], reverse=True)

    # Calculate totals
    iterm_total = sum(c for _, c in iterm_symbols)
    system_total = sum(c for _, c in system_symbols)
    other_total = sum(c for _, c in other_symbols)

    # Print report
    print("=" * 70)
    print("Self-Time Analysis Report")
    print("=" * 70)
    print()

    # First show iTerm2-attributed samples (most actionable)
    if iterm_attributed or unattributed_stacks:
        attributed_total = sum(iterm_attributed.values())
        stacks_total = attributed_total + unattributed_stacks
        attributed_sorted = sorted(iterm_attributed.items(), key=lambda x: x[1], reverse=True)

        print("-" * 70)
        print("iTerm2 CALLERS (attributed from call stacks)")
        print("-" * 70)
        print("iTerm2 functions whose call stacks lead to CPU usage:")
        print()
        print(f"{'Samples':>10}  {'%':>6}  Function")
        print(f"{'-'*10}  {'-'*6}  {'-'*50}")

        for symbol, count in attributed_sorted[:25]:
            pct = 100 * count / attributed_total if attributed_total else 0
            print(f"{count:>10,}  {pct:>5.1f}%  {symbol}")

        print()
        print(f"Stack samples: {stacks_total:,} total")
        print(f"  Attributed to iTerm2: {attributed_total:,} ({100*attributed_total/stacks_total:.1f}%)")
        print(f"  No iTerm2 frame:      {unattributed_stacks:,} ({100*unattributed_stacks/stacks_total:.1f}%)")
        print()

    print("-" * 70)
    print("RAW SELF-TIME (what's actually executing)")
    print("-" * 70)
    print()
    print(f"Total samples: {total_samples:,}")
    print(f"  iTerm2 code:  {iterm_total:>8,} ({100*iterm_total/total_samples:5.1f}%)")
    print(f"  System code:  {system_total:>8,} ({100*system_total/total_samples:5.1f}%)")
    print(f"  Other code:   {other_total:>8,} ({100*other_total/total_samples:5.1f}%)")
    print()

    print("-" * 70)
    print("TOP ACTIONABLE FUNCTIONS (iTerm2 code - raw self-time)")
    print("-" * 70)
    print(f"{'Samples':>10}  {'Self%':>6}  Function")
    print(f"{'-'*10}  {'-'*6}  {'-'*50}")

    for symbol, count in iterm_symbols[:25]:
        pct = 100 * count / total_samples
        print(f"{count:>10,}  {pct:>5.1f}%  {symbol}")

    if not iterm_symbols:
        print("  (no iTerm2 symbols found)")

    print()
    print("-" * 70)
    print("SYSTEM FUNCTIONS (exclusive leaf samples)")
    print("-" * 70)
    print(f"{'Samples':>10}  {'Self%':>6}  Function")
    print(f"{'-'*10}  {'-'*6}  {'-'*50}")

    for symbol, count in system_symbols[:15]:
        pct = 100 * count / total_samples
        print(f"{count:>10,}  {pct:>5.1f}%  {symbol}")

    print()
    print("-" * 70)
    print("OTHER LEAF FUNCTIONS (libraries, frameworks)")
    print("-" * 70)
    print(f"{'Samples':>10}  {'Self%':>6}  Function")
    print(f"{'-'*10}  {'-'*6}  {'-'*50}")

    for symbol, count in other_symbols[:15]:
        pct = 100 * count / total_samples
        print(f"{count:>10,}  {pct:>5.1f}%  {symbol}")



def main():
    """Main entry point."""
    # Read all input
    if len(sys.argv) > 1:
        with open(sys.argv[1], 'r') as f:
            lines = f.readlines()
    else:
        lines = sys.stdin.readlines()

    if not lines:
        print("Usage: python3 analyze_self_time.py [dtrace_output.txt]")
        print("   or: dtrace ... | python3 analyze_self_time.py")
        sys.exit(1)

    self_time_counts, iterm_attributed, unattributed_stacks = parse_dtrace_output(lines)
    analyze_and_report(self_time_counts, iterm_attributed, unattributed_stacks)


if __name__ == '__main__':
    main()
