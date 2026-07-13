#!/usr/bin/env python3
"""Animate a single character on an otherwise static full screen.

This is the case the per-row draw cache is built to win: the screen is painted
once with static content, then each frame only ONE cell changes (a spinner). Every
unchanged row hits the cache and is NOT rebuilt; only the row holding the animating
cell is rebuilt. Expect a hit rate near (rows-1)/rows -- e.g. ~98% on a 50-row
window -- versus 0% for fullscreen_ascii_animation.py.

Usage:
    tests/single_char_animation.py            # spinner cycles in one fixed cell
    tests/single_char_animation.py --bounce   # spinner also moves (dirties 2 rows/frame)
    tests/single_char_animation.py --fps 30   # cap frame rate (default 60)

Maximize/fullscreen the window first. Ctrl-C to stop; it prints achieved fps.
"""
import argparse
import shutil
import sys
import time


def static_char(x):
    # Deterministic non-blank content for column x, so a bouncing spinner can
    # restore the cell it leaves to exactly what fill_static wrote there.
    return chr(33 + (x % 94))


def fill_static(cols, rows):
    parts = ["\x1b[H"]
    line = "".join(static_char(x) for x in range(cols))
    for y in range(rows):
        parts.append(line)
        if y != rows - 1:
            parts.append("\r\n")
    return "".join(parts)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--fps", type=float, default=60.0)
    parser.add_argument("--bounce", action="store_true",
                        help="move the animating cell around instead of cycling in place")
    args = parser.parse_args()
    budget = (1.0 / args.fps) if args.fps > 0 else 0.0

    cols, rows = shutil.get_terminal_size()
    sys.stdout.write("\x1b[?25l")           # hide cursor (no blink to dirty a row)
    sys.stdout.write(fill_static(cols, rows))
    sys.stdout.flush()

    spinner = "|/-\\"
    x, y = cols // 2, rows // 2
    dx, dy = 1, 1
    i = 0
    frames = 0
    start = time.time()
    try:
        while True:
            t0 = time.time()
            if args.bounce:
                # Restore the cell we're leaving to its static content, then advance.
                sys.stdout.write("\x1b[%d;%dH%s" % (y + 1, x + 1, static_char(x)))
                x += dx
                y += dy
                if x <= 0 or x >= cols - 1:
                    dx = -dx
                if y <= 0 or y >= rows - 1:
                    dy = -dy
            # Draw the animating glyph (reverse video so it's easy to see).
            sys.stdout.write("\x1b[%d;%dH\x1b[7m%s\x1b[0m" %
                             (y + 1, x + 1, spinner[i % len(spinner)]))
            sys.stdout.flush()
            i += 1
            frames += 1
            if budget:
                remaining = budget - (time.time() - t0)
                if remaining > 0:
                    time.sleep(remaining)
    except KeyboardInterrupt:
        pass
    finally:
        elapsed = time.time() - start
        sys.stdout.write("\x1b[0m\x1b[?25h\x1b[2J\x1b[H")
        if elapsed > 0:
            sys.stderr.write("Rendered %d frames in %.1fs = %.1f fps\n" %
                             (frames, elapsed, frames / elapsed))
        sys.stdout.flush()


if __name__ == "__main__":
    main()
