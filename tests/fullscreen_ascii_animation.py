#!/usr/bin/env python3
"""Full-screen ASCII animation stress test for issue 12763.

Bellavene reported 8-14 fps on a maximized window running an "ASCII animation"
but never attached the actual program (only a CPU sample). This reproduces the
same worst case: every cell on the screen changes every frame, so the per-row
draw cache gets 0% hits and the full per-row build cost (attributed-string
construction, color conversion, glyph emission) is paid for every visible row on
every frame -- exactly the path the sample is hot in.

Usage:
    tests/fullscreen_ascii_animation.py            # monochrome
    tests/fullscreen_ascii_animation.py --color    # random fg color per cell
                                                     (stresses the color path)
    tests/fullscreen_ascii_animation.py --fps 30   # cap frame rate (default: uncapped)

Maximize/fullscreen the window first. Ctrl-C to stop.
"""
import argparse
import random
import shutil
import sys
import time

CHARSET = [chr(c) for c in range(33, 127)]  # printable ASCII, no space


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--color", action="store_true",
                        help="emit a random 256-color foreground per cell")
    parser.add_argument("--fps", type=float, default=0.0,
                        help="cap frame rate (0 = as fast as the terminal allows)")
    args = parser.parse_args()

    frame_budget = (1.0 / args.fps) if args.fps > 0 else 0.0
    sys.stdout.write("\x1b[?25l")  # hide cursor
    frames = 0
    start = time.time()
    try:
        while True:
            t0 = time.time()
            cols, rows = shutil.get_terminal_size()
            parts = ["\x1b[H"]  # cursor home (overwrite in place, no scrolling)
            for y in range(rows):
                if args.color:
                    for _ in range(cols):
                        parts.append("\x1b[38;5;%dm%s" % (random.randint(16, 231),
                                                          random.choice(CHARSET)))
                else:
                    parts.append("".join(random.choice(CHARSET) for _ in range(cols)))
                if y != rows - 1:
                    parts.append("\r\n")
            sys.stdout.write("".join(parts))
            sys.stdout.flush()
            frames += 1
            if frame_budget:
                remaining = frame_budget - (time.time() - t0)
                if remaining > 0:
                    time.sleep(remaining)
    except KeyboardInterrupt:
        pass
    finally:
        elapsed = time.time() - start
        sys.stdout.write("\x1b[0m\x1b[?25h\x1b[2J\x1b[H")  # reset, show cursor, clear
        if elapsed > 0:
            sys.stderr.write("Rendered %d frames in %.1fs = %.1f fps\n" %
                             (frames, elapsed, frames / elapsed))
        sys.stdout.flush()


if __name__ == "__main__":
    main()
