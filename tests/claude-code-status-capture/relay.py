# Runs a command in a pty, passes all I/O through, and logs OSC 7501 sequences in both directions
# with millisecond timestamps, decoding the base64 title and msg fields.
# Usage: relay.py LOGFILE COMMAND [ARG...]   e.g. relay.py ~/cc-status-capture/osc7501.log claude
# See README.md.
import base64, fcntl, os, pty, re, select, signal, sys, termios, time, tty

log = open(sys.argv[1], "a", buffering=1)
argv = sys.argv[2:]
pat = re.compile(rb"\x1b\]7501;([^\x1b\x07]*)(?:\x07|\x1b\\)")

def stamp():
    t = time.time()
    return time.strftime("%H:%M:%S", time.localtime(t)) + ".%03d" % int((t % 1) * 1000)

def decode(data):
    out = []
    for field in data.split(":"):
        k, sep, v = field.partition("=")
        if k in ("title", "msg") and sep:
            try:
                v = repr(base64.b64decode(v).decode("utf-8", "replace"))
            except Exception:
                pass
        out.append(k + sep + v)
    return " ".join(out)

def scan(buf, direction):
    while True:
        m = pat.search(buf)
        if not m:
            break
        log.write("%s %s 7501 %s\n" % (stamp(), direction, decode(m.group(1).decode("utf-8", "replace"))))
        buf = buf[m.end():]
    # Keep whatever could be the start of a sequence the next read finishes: one that has begun,
    # or a lone ESC at the very end.
    i = buf.rfind(b"\x1b]")
    if i >= 0 and len(buf) - i < 65536:
        return buf[i:]
    return b"\x1b" if buf.endswith(b"\x1b") else b""

pid, fd = pty.fork()
if pid == 0:
    os.execvp(argv[0], argv)

def winch(*_):
    size = fcntl.ioctl(0, termios.TIOCGWINSZ, b"\0" * 8)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, size)
    try:
        os.kill(pid, signal.SIGWINCH)
    except OSError:
        pass

winch()
signal.signal(signal.SIGWINCH, winch)
saved = termios.tcgetattr(0)
tty.setraw(0)
out_buf = in_buf = b""
try:
    while True:
        try:
            ready, _, _ = select.select([0, fd], [], [])
        except InterruptedError:
            continue
        if fd in ready:
            try:
                data = os.read(fd, 65536)
            except OSError:
                break
            if not data:
                break
            os.write(1, data)
            out_buf = scan(out_buf + data, "app->term")
        if 0 in ready:
            data = os.read(0, 65536)
            if not data:
                break
            os.write(fd, data)
            in_buf = scan(in_buf + data, "term->app")
finally:
    termios.tcsetattr(0, termios.TCSAFLUSH, saved)
# Exit as the command did.
_, status = os.waitpid(pid, 0)
sys.exit(os.waitstatus_to_exitcode(status) if hasattr(os, "waitstatus_to_exitcode") else status >> 8)
