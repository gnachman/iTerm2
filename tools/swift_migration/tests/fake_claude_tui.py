"""A stand-in for interactive Claude Code's input line, for the tests of
deadline_run.py's tmux mode and nightly_start.sh. Not a test itself.

Usage: python3 fake_claude_tui.py DIR [BANNER]

It puts its terminal in raw mode, as Claude Code does, then prints BANNER
if given, and models what was observed of Claude Code 2.1.331 idle at its
prompt in a private tmux server (2026-11-24):

- Keys typed go into an input line. Enter (CR) submits the line, except an
  Enter that arrives in the same burst as a long run of text (over
  PASTE_LENGTH characters with no pause of PASTE_GAP seconds): that burst
  is taken as a paste and the Enter becomes a newline inside the line, so
  the line stays unsubmitted. tmux's `send-keys -l TEXT ; send-keys Enter`
  in one call with a long TEXT did exactly that; the same text and Enter
  as two calls a second apart submitted it.
- Ctrl-C (0x03) with text in the line clears the line. With an empty line
  it does nothing the first time (Claude Code shows "Press Ctrl-C again to
  exit"); a second one within CTRL_C_WINDOW seconds exits, writing
  DIR/ctrl_c_exit.
- Escape (0x1b) is ignored here (it interrupts a turn in Claude Code; this
  stand-in has no turns, and Escape did not clear the line).
- A submitted line that is exactly /exit (after stripping) writes
  DIR/got_exit and exits 0. Any other submitted line is appended to
  DIR/lines; a line with a pasted newline is written with the newline
  shown as \\n.
- Turns (with $FAKE_TURN_SECONDS above 0): a submitted line starts a
  turn of that many seconds; a line submitted during a turn is queued, and
  the queue is delivered as the next turn when the turn ends. Escape during
  a turn ends it, and the queued lines are submitted at once as a new turn
  (both observed). Delivered lines go to DIR/lines in order.
- A dialog (with $FAKE_DIALOG set): open from the start, it takes the
  first submitted line as its answer (written to DIR/dialog_answer) and
  closes; the line is not delivered (observed with AskUserQuestion: the
  nudge typed into it was lost).
- Every byte read is appended to DIR/keys, raw.
- DIR/ready appears once the terminal is in raw mode. Keys typed before
  that are kept (cooked mode has completed their lines; a Ctrl-C typed
  then flushes the line being typed, as the terminal does, and is
  otherwise ignored).
"""

import os
import select
import signal
import sys
import termios
import time
import tty

PASTE_LENGTH = 100
PASTE_GAP = 0.05
CTRL_C_WINDOW = 2.0


def main():
    d = sys.argv[1]
    # Until the terminal is raw, a Ctrl-C typed into it is a SIGINT; it
    # must not end this stand-in, as it does not end Claude Code.
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd)
    # TCSANOW: keys typed before this point are kept, not flushed (a line
    # completed in cooked mode is read as it was typed).
    tty.setraw(fd, termios.TCSANOW)
    open(os.path.join(d, 'ready'), 'w').close()
    # The banner only now, so that whoever reacts to it types into a
    # terminal that is ready.
    if len(sys.argv) > 2:
        sys.stdout.write(sys.argv[2] + '\r\n')
        sys.stdout.flush()
    turn_seconds = float(os.environ.get('FAKE_TURN_SECONDS') or 0)
    dialog = bool(os.environ.get('FAKE_DIALOG'))
    turn_end = None
    queued = []
    line = ''
    burst = 0
    last_text = 0.0
    last_ctrl_c = None
    keys = open(os.path.join(d, 'keys'), 'ab')

    def finish(name):
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
        with open(os.path.join(d, name), 'w') as f:
            f.write('exit\n')
        sys.exit(0)

    def deliver(text):
        nonlocal turn_end
        with open(os.path.join(d, 'lines'), 'a') as f:
            f.write(text.replace('\n', '\\n') + '\n')
        if turn_seconds > 0:
            turn_end = time.monotonic() + turn_seconds

    def end_turn():
        nonlocal turn_end
        turn_end = None
        while queued and turn_end is None:
            deliver(queued.pop(0))

    while True:
        timeout = None if turn_end is None else max(0.0, turn_end - time.monotonic())
        ready, _, _ = select.select([fd], [], [], timeout)
        if not ready:
            end_turn()
            continue
        data = os.read(fd, 4096)
        if not data:
            termios.tcsetattr(fd, termios.TCSADRAIN, saved)
            return 0
        keys.write(data)
        keys.flush()
        now = time.monotonic()
        for ch in data.decode('utf-8', 'replace'):
            if ch in '\r\n':
                if burst > PASTE_LENGTH and now - last_text < PASTE_GAP:
                    line += '\n'
                    continue
                burst = 0
                if dialog:
                    with open(os.path.join(d, 'dialog_answer'), 'w') as f:
                        f.write(line + '\n')
                    dialog = False
                    line = ''
                    continue
                if line.strip() == '/exit':
                    finish('got_exit')
                if turn_end is not None:
                    queued.append(line)
                else:
                    deliver(line)
                line = ''
            elif ch == '\x03':
                if line:
                    line = ''
                elif last_ctrl_c is not None and now - last_ctrl_c < CTRL_C_WINDOW:
                    finish('ctrl_c_exit')
                else:
                    last_ctrl_c = now
                burst = 0
            elif ch == '\x1b':
                if turn_end is not None:
                    end_turn()
                continue
            else:
                if now - last_text > PASTE_GAP:
                    burst = 0
                line += ch
                burst += 1
                last_text = now


if __name__ == '__main__':
    sys.exit(main())
