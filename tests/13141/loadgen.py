#!/usr/bin/env python3
"""Write terminal output of a chosen kind to stdout, for loading iTerm2 while profiling or measuring.

Run it in a session:
    loadgen.py short                    short lines (numbers), as fast as possible
    loadgen.py long --line-length 300   300-character lines, which wrap in a narrow window
    loadgen.py sgr --mb 500             500 MB of text with frequent color changes, then stop
    loadgen.py unicode --seconds 30     30 seconds of wide, emoji, and combining characters
    loadgen.py mixed --rate 2           a mix of everything at 2 MB/s
    loadgen.py short --line-at-a-time   one write() per line, like a program that prints line by line
    loadgen.py --list                   the kinds, with what each stresses

By default output goes out in 64 KB writes, so the terminal rather than the producer or the kernel's
per-write cost is the bottleneck. --line-at-a-time makes one write() per line instead; the kernel's tty
layer then limits throughput (about 8 MB/s in total on macOS, however many sessions).

Output is a pregenerated chunk of about 1 MB, written over and over: cheap to produce, and the same in
every run with the same arguments. When it stops it prints the bytes written and the rate to stderr,
after resetting graphic renditions and the scroll region.
"""
import argparse
import os
import random
import sys
import time

KINDS = {
    "short": "Short lines (numbers 1, 2, 3, ...): line feeds and scrolling dominate.",
    "long": "Long ASCII lines (--line-length, default 500): appending, and wrapping when longer than the window.",
    "words": "Prose-like ASCII lines of varying length (20 to 120 characters).",
    "empty": "Empty lines only: the cost of a line feed by itself.",
    "sparse": "Mostly empty lines with an occasional short one.",
    "unicode": "Mixed wide (CJK), emoji, and combining characters.",
    "wide": "Only wide (CJK) characters.",
    "emoji": "Only emoji, including ones with variation selectors and ZWJ sequences.",
    "combining": "Latin letters with combining marks.",
    "rtl": "Hebrew and Arabic text mixed with Latin: bidirectional text.",
    "sgr": "A 16-color change every few characters: the parser and graphic renditions.",
    "truecolor": "A 24-bit color change every few characters, plus bold, italic, and underline.",
    "tabs": "Columns separated by tabs.",
    "cr": "Lines overwritten with carriage returns, like progress bars.",
    "fullscreen": "Whole-screen redraws by cursor addressing, as full-screen apps do: no scrollback.",
    "hyperlinks": "Text with OSC 8 hyperlinks.",
    "mixed": "All of the above, interleaved.",
}

LETTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
WIDE = "漢字仮名交じり文表示速度試験中日本語中文한국어測試"
EMOJI = ["😀", "🎉", "🚀", "🌍", "🔥", "✨", "❤️", "👍🏽", "👨‍👩‍👧", "🏳️‍🌈"]
COMBINING = ["é", "ä", "ô", "ñ", "ǘ", "ç"]
RTL = ["שלום", "עולם", "مرحبا", "بالعالم", "עברית", "العربية"]
WORDS = ["the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog", "terminal", "output", "line",
         "buffer", "scroll", "render", "token", "parse", "session", "window", "pane", "cursor"]

CHUNK_SIZE = 1 << 20


def make_chunk(kind, rng, line_length=500, width=80, height=24, start=1):
    """Returns about CHUNK_SIZE bytes of `kind` output. `start` is the first number for "short"."""
    if kind == "mixed":
        parts = []
        kinds = [k for k in KINDS if k not in ("mixed", "fullscreen")]
        size = 0
        while size < CHUNK_SIZE:
            part = make_lines(rng.choice(kinds), rng, line_length, width, height, 200, start)
            start += 200
            parts.append(part)
            size += len(part)
        return b"".join(parts)
    out = []
    size = 0
    while size < CHUNK_SIZE:
        part = make_lines(kind, rng, line_length, width, height, 1000, start)
        start += 1000
        out.append(part)
        size += len(part)
    return b"".join(out)


def make_lines(kind, rng, line_length, width, height, count, start):
    """Returns `count` lines (or, for fullscreen, frames) of `kind` output."""
    def letters(n):
        return "".join(rng.choices(LETTERS, k=n))

    if kind == "short":
        text = "".join(f"{i}\n" for i in range(start, start + count))
    elif kind == "long":
        text = "".join(letters(line_length) + "\n" for _ in range(count))
    elif kind == "words":
        lines = []
        for _ in range(count):
            line = []
            while sum(len(w) + 1 for w in line) < rng.randrange(20, 120):
                line.append(rng.choice(WORDS))
            lines.append(" ".join(line) + "\n")
        text = "".join(lines)
    elif kind == "empty":
        text = "\n" * count
    elif kind == "sparse":
        text = "".join((letters(rng.randrange(1, 20)) if rng.randrange(10) == 0 else "") + "\n" for _ in range(count))
    elif kind == "unicode":
        pools = [list(WIDE), EMOJI, COMBINING]
        text = "".join("".join(rng.choice(rng.choice(pools)) for _ in range(30)) + "\n" for _ in range(count))
    elif kind == "wide":
        text = "".join("".join(rng.choices(WIDE, k=35)) + "\n" for _ in range(count))
    elif kind == "emoji":
        text = "".join("".join(rng.choices(EMOJI, k=30)) + "\n" for _ in range(count))
    elif kind == "combining":
        text = "".join("".join(rng.choices(COMBINING, k=60)) + "\n" for _ in range(count))
    elif kind == "rtl":
        text = "".join(" ".join(rng.choice(RTL + WORDS) for _ in range(10)) + "\n" for _ in range(count))
    elif kind == "sgr":
        text = "".join("".join(f"\x1b[3{rng.randrange(8)};4{rng.randrange(8)}m{letters(4)}" for _ in range(18)) + "\x1b[m\n"
                       for _ in range(count))
    elif kind == "truecolor":
        def style():
            attrs = rng.choice(["", "1;", "3;", "4;", "1;3;"])
            fg = ";".join(str(rng.randrange(256)) for _ in range(3))
            bg = ";".join(str(rng.randrange(256)) for _ in range(3))
            return f"\x1b[{attrs}38;2;{fg};48;2;{bg}m"
        text = "".join("".join(style() + letters(4) for _ in range(18)) + "\x1b[m\n" for _ in range(count))
    elif kind == "tabs":
        text = "".join("\t".join(letters(rng.randrange(1, 8)) for _ in range(8)) + "\n" for _ in range(count))
    elif kind == "cr":
        lines = []
        for _ in range(count):
            for percent in range(0, 101, 10):
                bar = "#" * (percent * 50 // 100)
                lines.append(f"\r[{bar:<50}] {percent:3}%")
            lines.append("\n")
        text = "".join(lines)
    elif kind == "fullscreen":
        frames = []
        for _ in range(max(1, count // height)):
            rows = "".join(f"\x1b[{row};1H{letters(width - 1)}" for row in range(1, height + 1))
            frames.append("\x1b[H" + rows)
        text = "".join(frames)
    elif kind == "hyperlinks":
        text = "".join(f"see \x1b]8;;https://example.com/{letters(8)}\x1b\\{letters(12)}\x1b]8;;\x1b\\ for details\n"
                       for _ in range(count))
    else:
        raise SystemExit(f"Unknown kind {kind}; see --list")
    return text.encode("utf-8")


def split_into_writes(chunk, size):
    """Splits chunk into pieces of about `size` bytes that end on UTF-8 character boundaries, so
    stopping after any write never leaves the terminal holding part of a character."""
    pieces = []
    start = 0
    while start < len(chunk):
        end = min(len(chunk), start + size)
        # Back up over continuation bytes (10xxxxxx) to the start of the character the cut is in.
        while end < len(chunk) and end > start and (chunk[end] & 0xC0) == 0x80:
            end -= 1
        pieces.append(chunk[start:end])
        start = end
    return pieces


def terminal_size():
    # A pty nobody has sized (such as script's) reports 0 by 0.
    try:
        size = os.get_terminal_size(sys.stdout.fileno())
        return size.columns or 80, size.lines or 24
    except OSError:
        return 80, 24


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("kind", nargs="?", help="what to write; see --list")
    ap.add_argument("--list", action="store_true", help="list the kinds and what each stresses")
    ap.add_argument("--line-length", type=int, default=500, help="characters per line for long (default 500)")
    ap.add_argument("--mb", type=float, default=0, help="stop after this many MB (default: no limit)")
    ap.add_argument("--seconds", type=float, default=0, help="stop after this many seconds (default: no limit)")
    ap.add_argument("--rate", type=float, default=0, help="limit to this many MB/s (default: as fast as possible)")
    ap.add_argument("--line-at-a-time", action="store_true", help="one write() per line instead of 64 KB writes")
    ap.add_argument("--seed", type=int, default=13141, help="random seed, for repeatable output")
    args = ap.parse_args()

    if args.list or not args.kind:
        for kind, what in KINDS.items():
            print(f"  {kind:11} {what}")
        return 0 if args.list else 2
    if args.kind not in KINDS:
        raise SystemExit(f"Unknown kind {args.kind}; see --list")

    width, height = terminal_size()
    chunk = make_chunk(args.kind, random.Random(args.seed), args.line_length, width, height)
    if args.line_at_a_time:
        pieces = [line + b"\n" for line in chunk.split(b"\n") if line] or [chunk]
        if args.kind == "empty":
            pieces = [b"\n"] * len(chunk)
    else:
        pieces = split_into_writes(chunk, 65536)

    limit = int(args.mb * 1e6) if args.mb else None
    fd = sys.stdout.fileno()
    written = 0
    start = time.monotonic()
    deadline = start + args.seconds if args.seconds else None
    try:
        while True:
            for piece in pieces:
                if limit is not None and written >= limit:
                    raise StopIteration
                if deadline is not None and time.monotonic() >= deadline:
                    raise StopIteration
                if args.rate:
                    ahead = written / (args.rate * 1e6) - (time.monotonic() - start)
                    if ahead > 0:
                        time.sleep(ahead)
                os.write(fd, piece)
                written += len(piece)
    except (StopIteration, KeyboardInterrupt):
        pass
    except BrokenPipeError:
        return 0
    elapsed = max(1e-6, time.monotonic() - start)
    # Leave the terminal in a sane state: default renditions, no scroll region, cursor at the bottom.
    os.write(fd, b"\x1b[m\x1b[r" + f"\x1b[{height};1H\n".encode())
    print(f"{args.kind}: {written / 1e6:.1f} MB in {elapsed:.1f}s, {written / 1e6 / elapsed:.1f} MB/s", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
