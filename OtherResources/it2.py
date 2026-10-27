#!/usr/bin/env python3
"""Remote `it2` client for iTerm2 SSH integration.

When you are ssh'd into a host via iTerm2's SSH integration, the conductor's
framer.py exports a unix domain socket (path in $IT2_SOCK) that proxies to the
local iTerm2. This tiny stdlib-only client just forwards argv + terminal context
to the local machine, where the *real* it2 command tree (embedded in iTerm2) runs
and dispatches to the API server; stdout/stderr/exit stream back. The client never
builds an API request itself, so it stays trivially in sync with the Swift it2.

Wire protocol (this client <-> framer socket), length-prefixed frames:

    [1 byte type][4 byte big-endian payload length][payload]

Upstream (client -> iTerm2):
    'H' HELLO   json: {protocol, nonce, argv, cwd, term, isatty, cols, rows, env, stdin}
    'C' CANCEL  empty  (SIGINT; used by long-running/monitor commands)

Downstream (iTerm2 -> client):
    'O' STDOUT  raw bytes
    'E' STDERR  raw bytes
    'X' EXIT    json: {code}   (last frame; connection then closes)

Requires only the Python standard library and Python 3.7+ (guaranteed present:
the framer this talks to already runs under it).
"""

import base64
import json
import os
import shutil
import signal
import socket
import struct
import subprocess
import sys
import time

HELLO = b"H"
# Sent in the HELLO. iTerm2 serves this version and older, and refuses a newer client with an
# explanation instead of running it half understood. Bump it, together with the app's
# ConductorIT2Demux.protocolVersion, when the HELLO gains something a command cannot run
# correctly without. A HELLO with no "protocol" predates the field and counts as older.
PROTOCOL_VERSION = 1
CANCEL = b"C"
STDOUT = ord("O")
STDERR = ord("E")
EXIT = ord("X")

# A declared frame length above this is treated as a local framing desync (a data byte misread
# as a length prefix) and aborted, rather than trying to buffer toward the 4 GiB u32 maximum.
# Generous, because a legitimate down-frame carries one output line, which can be large (e.g.
# `it2 session read` of a very long line); the payload-read timeout below is the real stall
# guard, this just gives an immediate, clear error for an obviously bogus length.
MAX_FRAME_LENGTH = 256 * 1024 * 1024
# Once a header declares a payload length, its bytes should arrive promptly. If the read
# stalls mid-payload (a desync, or an unresponsive peer), time out and surface an error instead
# of blocking forever on a recv that PEP 475 keeps retrying (which also swallows the first
# Ctrl-C). This deliberately does NOT apply to the idle wait for the next frame's header -- a
# long-running `monitor --follow` legitimately idles between frames.
PAYLOAD_READ_TIMEOUT = 30

# True while the main thread is inside send_frame. it2.py spawns no threads, so the only
# possible re-entry is the SIGINT handler firing on this same thread while a frame is being
# sent. on_sigint checks this flag and returns early when it is set, so it never re-enters
# send_frame -- which is why no lock is needed: the send path is only ever touched by one
# thread, and that thread never re-enters it.
_sending = False


def send_frame(sock, ftype, payload=b""):
    global _sending
    if isinstance(payload, str):
        payload = payload.encode("utf-8")
    header = ftype + struct.pack(">I", len(payload))
    # Set the flag before the send so the signal handler can never observe "not sending"
    # while we are in the middle of writing a frame.
    _sending = True
    try:
        sock.sendall(header + payload)
    finally:
        _sending = False


def recv_exact(sock, n, deadline=None):
    # If `deadline` (a time.monotonic() timestamp) is given, the WHOLE read must finish by then:
    # each recv gets the remaining budget as its timeout, so a slow trickle cannot keep resetting
    # a per-recv idle timer. Without a deadline the socket's current timeout applies (the callers'
    # header read leaves it unset -> blocking, which idling between frames needs).
    chunks = []
    remaining = n
    while remaining > 0:
        if deadline is not None:
            budget = deadline - time.monotonic()
            if budget <= 0:
                raise socket.timeout("payload read deadline exceeded")
            sock.settimeout(budget)
        chunk = sock.recv(remaining)
        if not chunk:
            return None
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def recv_frame(sock):
    # The header read has no timeout on purpose: idling between frames is normal for a
    # streaming command (monitor --follow), so a stalled next-frame wait must not abort.
    header = recv_exact(sock, 5)
    if header is None:
        return None, None
    ftype = header[0]
    length = struct.unpack(">I", header[1:5])[0]
    if length > MAX_FRAME_LENGTH:
        eprint("it2: framing error (declared frame length %d exceeds maximum); aborting.\n" % length)
        return None, None
    if not length:
        return ftype, b""
    # The payload, unlike the next-frame wait, should arrive promptly; bound the WHOLE read with
    # a single deadline. A per-recv idle timeout would be reset by every chunk, so a slow-trickle
    # desync (small frames misread as payload bytes, each arriving <timeout apart) would never
    # surface -- the deadline bounds the total read time regardless of chunk pacing.
    deadline = time.monotonic() + PAYLOAD_READ_TIMEOUT
    try:
        payload = recv_exact(sock, length, deadline=deadline)
    except (socket.timeout, TimeoutError, OSError):
        eprint("it2: framing error (stalled reading a %d-byte frame payload); aborting.\n" % length)
        payload = None
    finally:
        try:
            sock.settimeout(None)
        except OSError:
            pass
    if payload is None:
        return None, None
    return ftype, payload


def terminal_size():
    # sys.stdout is None when stdout is closed before exec (e.g. `it2 foo >&-`), so
    # sys.stdout.fileno() raises AttributeError. A stream closed in-process raises
    # ValueError, and other stream failures OSError. Any of these means "no terminal".
    try:
        size = os.get_terminal_size(sys.stdout.fileno())
        return size.columns, size.lines
    except (AttributeError, OSError, ValueError):
        return 0, 0


def safe_getcwd():
    # FileNotFoundError (an OSError) if the working directory was removed.
    try:
        return os.getcwd()
    except OSError:
        return ""


def safe_isatty():
    # sys.stdout may be None (closed before exec) -> AttributeError; closed in-process
    # -> ValueError; other failures -> OSError.
    try:
        return sys.stdout.isatty()
    except (AttributeError, ValueError, OSError):
        return False


# Streams that have taken at least one successful write. A write failure on such a
# stream is a mid-stream break (a downstream consumer that exited -> broken pipe, or a
# full disk) that should stop us like SIGPIPE on a local pipeline; a failure on a stream
# that never worked (>&-, closed before exec) is tolerated and dropped as before.
_usable_streams = set()


def write_raw(stream, payload):
    # Returns True to keep going (wrote, or harmlessly dropped on a never-usable stream),
    # False if the stream broke so the caller stops like SIGPIPE.
    try:
        stream.buffer.write(payload)
        stream.buffer.flush()
        _usable_streams.add(id(stream))
        return True
    except (BrokenPipeError, ConnectionResetError):
        # A broken pipe / reset means a real downstream consumer existed and went away (e.g.
        # `it2 cmd | head -c0` or a pager quit closing the read end before our FIRST write).
        # Treat that as broke even with no prior successful write -- otherwise the _usable_
        # streams heuristic below would misread it as "never usable, drop harmlessly", silently
        # discarding all output, never sending CANCEL, and returning the wrong exit code.
        return False
    except (AttributeError, ValueError, OSError):
        # stream is None / closed in-process (AttributeError/ValueError), or a non-pipe OSError
        # like EBADF from `>&-` / closed-before-exec. Tolerate a failure on a stream that never
        # worked (drop, keep going); only a previously-good stream breaking stops us.
        return id(stream) not in _usable_streams


def eprint(message):
    # Same None/closed-stream tolerance for our own diagnostics (e.g. `it2 foo 2>&-`).
    try:
        sys.stderr.write(message)
    except (AttributeError, ValueError, OSError):
        pass


# Records that attached iTerm2 controllers publish on a tmux server, one global user option
# per attached client: @it2_client_<hex of tmux client name> = c_<hex of JSON>. Keep these in
# step with TmuxController's advertiseIT2Client in the iTerm2 app and with it2cli's
# TmuxOwnership.swift, the local counterpart of this code.
TMUX_IT2_CLIENT_OPTION_PREFIX = "@it2_client_"
TMUX_IT2_CLIENT_RECORD_TAG = "c_"
# Marks list-clients lines in the combined query output so they cannot be confused with
# show-options lines.
TMUX_CLIENT_LINE_PREFIX = "IT2CLIENT"
# Marks the one line naming the tmux session that holds this pane.
TMUX_PANE_SESSION_LINE_PREFIX = "IT2PANESESSION"


def tmux_query_arguments(socket_path, pane, tmux="tmux"):
    """argv for one tmux invocation: the attached clients, the global options, and which
    tmux session holds `pane` (skipped when there is no pane).

    A bare ";" argument separates commands in a sequence, so they all run in one client. The
    formats carry real tab characters: tmux does not interpret backslash escapes in a
    format string.

    client_session is what lets the caller reach the connection that can actually place its
    pane. A tmux server can have several attached control-mode clients, each driving a
    DIFFERENT tmux session over its own ssh connection, and only the one attached to the
    pane's session can show it.
    """
    fmt = "\t".join([TMUX_CLIENT_LINE_PREFIX, "#{client_name}", "#{client_control_mode}",
                     "#{client_created}", "#{client_session}"])
    args = [tmux, "-S", socket_path, "list-clients", "-F", fmt, ";", "show-options", "-g"]
    if pane:
        args += [";", "display-message", "-p", "-t", pane,
                 TMUX_PANE_SESSION_LINE_PREFIX + "\t#{session_id}"]
    return args


def parse_tmux_client_records(output):
    """The records of iTerm2 clients currently attached to a tmux server, newest first.

    Parses the combined output of tmux_query_arguments. A record counts only if its
    client is still attached in control mode, so a record that was never removed (its
    iTerm2 crashed, its ssh connection dropped) is ignored rather than tried. Anything
    malformed is skipped: a record is advisory and must not take down the lookup for the
    well-formed ones next to it.
    """
    attached_at = {}      # client name -> attach time, attached control-mode clients only
    client_session = {}   # client name -> the tmux session it is attached to
    records = {}          # client name -> record dict
    pane_session = None   # the tmux session holding this pane, when it could be determined
    for line in output.splitlines():
        if line.startswith(TMUX_PANE_SESSION_LINE_PREFIX + "\t"):
            pane_session = line.split("\t", 1)[1].strip()
            continue
        if line.startswith(TMUX_CLIENT_LINE_PREFIX + "\t"):
            fields = line.split("\t")
            if len(fields) < 4:
                continue
            name, control_mode, created = fields[1], fields[2], fields[3]
            # Absent on tmux too old for #{client_session}; then nothing is preferred and
            # the newest-attacher order below stands on its own.
            if len(fields) >= 5 and fields[4]:
                client_session[name] = fields[4]
            # A missing client_control_mode (very old tmux prints nothing for an unknown
            # format) is accepted; only an explicit 0 rejects.
            if control_mode == "0":
                continue
            try:
                attached_at[name] = int(created)
            except ValueError:
                attached_at[name] = 0
            continue
        if not line.startswith(TMUX_IT2_CLIENT_OPTION_PREFIX):
            continue
        option, _sep, value = line.partition(" ")
        value = value.strip()
        # show-options only quotes a value that needs it, and ours never does, but strip
        # quotes anyway in case that changes.
        if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
            value = value[1:-1]
        if not value.startswith(TMUX_IT2_CLIENT_RECORD_TAG):
            continue
        try:
            name = bytes.fromhex(option[len(TMUX_IT2_CLIENT_OPTION_PREFIX):]).decode("utf-8")
            record = json.loads(
                bytes.fromhex(value[len(TMUX_IT2_CLIENT_RECORD_TAG):]).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            continue
        if isinstance(record, dict):
            records[name] = record
    # Newest attach first; name as a tiebreaker so the order is deterministic.
    ordered = sorted(attached_at, key=lambda n: (-attached_at[n], n))
    # Then float the clients attached to the session that holds this pane. Only those can
    # place it: a client attached to another session of the same server will answer "no
    # session is showing that tmux pane" however recently it attached. Newest-first was the
    # whole rule before, which is why creating a second tmux session silently redirected
    # every call to a connection that could not serve it (2026-09-28).
    #
    # A stable sort, so newest-first still orders within each group, and the others stay as
    # fallbacks rather than being dropped: the preferred client's socket may be gone.
    if pane_session:
        ordered.sort(key=lambda n: 0 if client_session.get(n) == pane_session else 1)
    return [records[n] for n in ordered if n in records]


def tmux_executable(server_pid, which=shutil.which):
    """The tmux to ask. On Linux, the tmux server's own executable through /proc, which is the
    same tmux even after an upgrade replaced the file, so client and server speak the same
    protocol. Else the one on PATH. Else, as for a tmux started by its full path (Homebrew's,
    with /opt/homebrew/bin not on PATH), the server's executable as ps names it, trusted only
    when that is an absolute path. None when no tmux can be found."""
    if server_pid.isdigit():
        exe = "/proc/%s/exe" % server_pid
        if os.access(exe, os.X_OK):
            return exe
    found = which("tmux")
    if found:
        return found
    if not server_pid.isdigit():
        return None
    try:
        result = subprocess.run(["ps", "-o", "comm=", "-p", server_pid],
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                stdin=subprocess.DEVNULL, timeout=2)
        comm = result.stdout.decode("utf-8", "replace").strip()
    except (OSError, subprocess.SubprocessError):
        return None
    if os.path.isabs(comm) and os.access(comm, os.X_OK):
        return comm
    return None


# Why tmux_advertised_client_records last returned None, for the message main() prints.
TMUX_LOOKUP_FAILURE = None


def tmux_advertised_client_records():
    """The records of the iTerm2 clients attached to this pane's tmux server, newest first.

    A pane inherits IT2_SOCK/IT2_NONCE from the tmux server, which froze them when it
    started. They name whichever ssh connection happened to start the server, which
    after a detach and a reattach from another connection, or an iTerm2 relaunch, is
    not the one showing the pane and may not exist at all. So each tmux -CC controller
    publishes its own socket and nonce on the server when it attaches, and this client
    looks there first. Only records whose client is still attached are returned, newest
    attacher first, which matches the app's rule that the last attacher owns the pane;
    the caller tries each in turn and falls back to the pane's own environment last.

    Returns [] when not inside tmux or when no attached client has advertised, and None
    when inside tmux but the server could not be asked (no tmux found, or it did not answer;
    a wedged server must not hang every it2 call, hence the timeout). The caller must not then
    treat the inherited socket as this pane's: it belongs to whichever connection started the
    server, and a command sent there acts on that connection's session instead.
    """
    tmux = os.environ.get("TMUX")
    if not tmux:
        return []
    # $TMUX is "<socket path>,<server pid>,<session id>"; the path may itself contain
    # commas, so it is everything before the LAST two fields.
    fields = tmux.split(",")
    if len(fields) < 3:
        return []
    socket_path = ",".join(fields[:-2])
    if not socket_path:
        return []
    global TMUX_LOOKUP_FAILURE
    executable = tmux_executable(fields[-2])
    if executable is None:
        TMUX_LOOKUP_FAILURE = "not found"
        return None
    try:
        result = subprocess.run(
            tmux_query_arguments(socket_path, os.environ.get("TMUX_PANE", ""), executable),
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
            timeout=2)
    except (OSError, subprocess.SubprocessError):
        TMUX_LOOKUP_FAILURE = "no answer"
        return None
    # A server that answers always prints its global options, so nothing at all with a failure
    # means it was never reached (no server there, a tmux that speaks another protocol version,
    # a socket this user can't open).
    if result.returncode != 0 and not result.stdout.strip():
        TMUX_LOOKUP_FAILURE = "no answer"
        return None
    # Parse whatever came back, even on a nonzero exit. The pane query is part of the same
    # invocation, so a stale or closed $TMUX_PANE makes tmux exit nonzero, and bailing here
    # would throw away the client records the earlier commands already printed -- turning a
    # pane that merely went away into "no iTerm2 is attached". Errors go to stderr, which is
    # discarded, and the parser skips anything it does not recognize.
    return parse_tmux_client_records(result.stdout.decode("utf-8", "replace"))


def connect_to_iterm2(candidates):
    """Connect to the first candidate that accepts. Returns (socket, nonce) or (None, error).

    A candidate is a record with "sock" and "nonce". Both come from the same record, so
    a socket is never paired with another connection's nonce. A refused or missing
    socket moves on to the next candidate; the pane's own environment is normally last.
    """
    sock, candidate = connect_to_candidate(candidates)
    if sock is None:
        return None, candidate
    nonce = candidate.get("nonce")
    return sock, (nonce if isinstance(nonce, str) else "")


# Set in the environment of a re-exec, so a copy that disagrees about which file it is cannot
# bounce back and forth.
REEXEC_GUARD_NAME = "IT2_REEXECED"


def reexec_path(candidate, own_path, env):
    """The interpreter to hand this invocation to, or None to keep running this one.

    A tmux pane inherits IT2_PY from the tmux server, frozen when whichever connection started
    it. That copy may be older or newer than the iTerm2 now attached, so each controller's
    record names the it2.py ITS connection uploaded as "py", and once a connection is chosen
    the matching copy runs the command. Version and connection are then chosen together.

    Only an absolute path to a file that exists, is not this file, and only once.
    """
    path = candidate.get("py")
    if not isinstance(path, str) or not os.path.isabs(path):
        return None
    if env.get(REEXEC_GUARD_NAME):
        return None
    try:
        if os.path.realpath(path) == os.path.realpath(own_path):
            return None
    except (OSError, ValueError):
        return None
    if not os.path.isfile(path):
        return None
    return path


def reexec(path, argv, env):
    """Replace this process with `path` running `argv`. Returns only if exec failed."""
    child_env = dict(env)
    child_env[REEXEC_GUARD_NAME] = "1"
    # So the copy reports itself, not the server's stale value, to the app.
    child_env["IT2_PY"] = path
    interpreter = sys.executable or "python3"
    try:
        os.execve(interpreter, [interpreter, path] + list(argv), child_env)
    except OSError:
        pass


def connect_to_candidate(candidates):
    """Like connect_to_iterm2, but returns the whole record that accepted: (socket, record)
    or (None, error)."""
    last_error = None
    for candidate in candidates:
        path = candidate.get("sock")
        if not isinstance(path, str) or not path:
            continue
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            sock.connect(path)
        except OSError as e:
            last_error = "%s: %s" % (path, e)
            try:
                sock.close()
            except OSError:
                pass
            continue
        return sock, candidate
    return None, last_error


# Stdin is forwarded whole in the HELLO frame, so it has to be bounded. A Claude Code
# PostToolUse payload can carry a large tool result, so this is generous; the framer's own frame
# cap is 16 MiB, well above it.
MAX_STDIN_BYTES = 1024 * 1024

# The only variables sent to iTerm2. An allowlist, not a filter: the environment of a remote
# shell holds credentials, tokens and paths that have no business crossing to the Mac, and the
# app needs exactly these to address a session.
#   TMUX, TMUX_PANE  - which tmux pane this is, for pane addressing
#   TERM_SESSION_ID  - the session, when iTerm2 forked the job itself
#   IT2_SUITE        - which iTerm2 instance
#   IT2_PY           - which interpreter this connection uploaded
ALLOWED_ENV_NAMES = ("TMUX", "TMUX_PANE", "TERM_SESSION_ID", "IT2_SUITE", "IT2_PY")


def allowed_environment(env):
    """The allowlisted subset of `env`. Absent names are omitted rather than sent empty, so the
    app can tell "unset" from "set to nothing"."""
    return {name: env[name] for name in ALLOWED_ENV_NAMES if name in env}


# The only subcommand whose payload arrives on stdin. Reading stdin for ANY command would hang
# the ones that do not expect it: stdin is often an inherited pipe that never reaches EOF (a
# script, a test harness, a program that keeps its end open), and read() would block forever.
# Found exactly that way -- `it2 session list` timed out in tests/it2py_test.py the moment this
# was unconditional.
STDIN_CONSUMING_COMMANDS = ("handle-agent-hook",)


def wants_stdin(argv):
    """Whether this invocation's command reads a payload from stdin."""
    for argument in argv:
        if argument.startswith("-"):
            continue
        return argument in STDIN_CONSUMING_COMMANDS
    return False


def read_stdin_payload(stream):
    """Stdin's bytes when it is not a tty, else None.

    A hook is invoked with its payload on stdin, so a remote `it2 handle-agent-hook` needs it.
    An interactive invocation must never be drained: `it2 handle-agent-hook` typed at a prompt
    would block until the user sent EOF. Unreadable stdin is not an error; the command simply
    has no payload.

    Only called for a command in STDIN_CONSUMING_COMMANDS; see wants_stdin.
    """
    try:
        if stream is None or stream.isatty():
            return None
    except (OSError, ValueError):
        return None
    try:
        buffer = getattr(stream, "buffer", stream)
        data = buffer.read(MAX_STDIN_BYTES)
    except (OSError, ValueError):
        return None
    if not data:
        return None
    return data


def main():
    candidates = tmux_advertised_client_records()
    if candidates is None:
        if TMUX_LOOKUP_FAILURE == "not found":
            eprint("it2: can\u2019t find tmux to ask this tmux server which iTerm2 is showing "
                   "this pane, so it can\u2019t tell which connection to use. Put tmux on PATH "
                   "and try again.\n")
        else:
            eprint("it2: this tmux server did not say which iTerm2 is showing this pane, so "
                   "it2 can\u2019t tell which connection to use.\n")
        return 2
    # The pane's own environment comes last: it is right for a tmux server no iTerm2 has
    # attached to with tmux -CC (plain tmux in an SSH Integration session), and a fallback
    # when every advertised socket is gone.
    own_sock_path = os.environ.get("IT2_SOCK")
    if own_sock_path:
        candidates.append({"sock": own_sock_path, "nonce": os.environ.get("IT2_NONCE", "")})
    if not candidates:
        eprint("it2: not running under iTerm2 SSH integration (IT2_SOCK is unset).\n")
        return 2

    try:
        sock, candidate = connect_to_candidate(candidates)
        if sock is not None:
            path = reexec_path(candidate, os.path.abspath(__file__), os.environ)
            if path:
                # Connected only to learn which record answers; the copy connects for itself.
                # Stdin has not been touched yet, so it reaches the copy intact.
                sock.close()
                reexec(path, sys.argv[1:], os.environ)
                # The exec failed. Carry on as this copy rather than fail the command.
                sock, candidate = connect_to_candidate(candidates)
    except KeyboardInterrupt:
        return 130
    if sock is None:
        eprint("it2: cannot reach iTerm2 (%s)\n" % candidate)
        return 2
    nonce = candidate.get("nonce")
    if not isinstance(nonce, str):
        nonce = ""

    cols, rows = terminal_size()
    hello = {
        "protocol": PROTOCOL_VERSION,
        "nonce": nonce,
        "argv": sys.argv[1:],
        "cwd": safe_getcwd(),
        "term": os.environ.get("TERM", ""),
        "isatty": safe_isatty(),
        "cols": cols,
        "rows": rows,
        "env": allowed_environment(os.environ),
    }
    # In the HELLO itself, not a later frame: startCommand launches the command as soon as HELLO
    # arrives, so anything sent afterwards would race it.
    if wants_stdin(sys.argv[1:]):
        stdin_payload = read_stdin_payload(sys.stdin)
        if stdin_payload is not None:
            hello["stdin"] = base64.b64encode(stdin_payload).decode("ascii")
    try:
        send_frame(sock, HELLO, json.dumps(hello))
    except OSError as e:
        eprint("it2: connection lost: %s\n" % e)
        return 2
    except KeyboardInterrupt:
        return 130

    # First Ctrl-C asks the server to cancel; restoring the default handler means
    # a second Ctrl-C kills the client for real, so an unanswered or hung server
    # can never make it2 uninterruptible.
    def on_sigint(_signum, _frame):
        signal.signal(signal.SIGINT, signal.SIG_DFL)  # a second Ctrl-C is fatal
        if _sending:
            # A frame is already being sent on this (the main) thread -- e.g. the broken-
            # pipe path is sending CANCEL. Sending again now would re-enter the non-
            # reentrant send path and deadlock (or corrupt the in-flight frame). Skip it:
            # SIG_DFL is restored, and a CANCEL is already on its way in the send case.
            return
        try:
            # recv_exact may have left a short payload-read timeout on this shared socket; clear
            # it so this CANCEL's sendall is never swallowed by an inherited read timeout (which
            # would silently drop the user's cancel while the connection is alive).
            sock.settimeout(None)
            send_frame(sock, CANCEL)
        except OSError:
            pass

    signal.signal(signal.SIGINT, on_sigint)

    exit_code = 0
    saw_exit = False
    broken = False
    while True:
        ftype, payload = recv_frame(sock)
        if ftype is None:
            break
        if ftype == STDOUT:
            if not write_raw(sys.stdout, payload):
                broken = True
                break
        elif ftype == STDERR:
            if not write_raw(sys.stderr, payload):
                broken = True
                break
        elif ftype == EXIT:
            saw_exit = True
            try:
                obj = json.loads(payload.decode("utf-8"))
                # Tolerate a payload that is valid JSON but not an object (e.g. a
                # bare number/string/null): .get would raise AttributeError.
                exit_code = int(obj.get("code", 0)) if isinstance(obj, dict) else 0
            except (ValueError, TypeError):
                exit_code = 0
            break

    if broken:
        # A previously-good output stream broke mid-stream (downstream consumer exited,
        # like `it2 monitor -f | head`, or a full disk). Mirror a local pipeline's SIGPIPE:
        # ask the server to cancel a still-running command, then exit 128+SIGPIPE(13).
        try:
            send_frame(sock, CANCEL)
        except OSError:
            pass
        try:
            sock.close()
        except OSError:
            pass
        return 141

    try:
        sock.close()
    except OSError:
        pass

    if not saw_exit:
        # EXIT is contractually the last frame; a disconnect without it means the
        # command did not complete normally (server crash, killed job, reset).
        eprint("it2: connection closed before completion.\n")
        return 2
    return exit_code


def _silence_std_stream_flush():
    # Python flushes stdout/stderr during interpreter shutdown. If a downstream consumer
    # (e.g. `it2 monitor -f | head`) has exited, that flush hits the now-broken pipe again
    # and prints a spurious "Exception ignored in ... BrokenPipeError" traceback, even though
    # main() already handled the break and we are exiting cleanly. Flush each stream now,
    # swallowing the error, and point its fd at /dev/null so the shutdown flush stays silent.
    # (See the note on SIGPIPE in the Python docs.)
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.flush()
        except (BrokenPipeError, ValueError, OSError):
            try:
                os.dup2(os.open(os.devnull, os.O_WRONLY), stream.fileno())
            except (OSError, ValueError, AttributeError):
                pass


if __name__ == "__main__":
    try:
        code = main()
    except KeyboardInterrupt:
        # A Ctrl-C in the narrow window before main() installs its SIGINT handler (or after it
        # restores SIG_DFL) reaches here as an uncaught KeyboardInterrupt. Exit a clean 130
        # like a shell-interrupted process instead of dumping a traceback with status 1.
        code = 130
    _silence_std_stream_flush()
    sys.exit(code)
