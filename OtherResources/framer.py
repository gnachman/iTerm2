#!/usr/bin/env python3
import asyncio
import base64
import errno
import fcntl
import json
import os
import pty
import pwd
import random
import re
import signal
import stat
import subprocess
import sys
import termios
import time
import traceback

# pid -> Process
PROCESSES = {}
# List of pids that are completed. Their tasks can be awaited and removed.
COMPLETED = []
VERBOSE=0
LOGFILE=None
RUNLOOP=None
TASKS=[]
QUITTING=False
REGISTERED=[]
LASTPS={}
AUTOPOLL = 0
AUTOPOLL_TASK = None
RECOVERY_STATE={}
# 0: Not blocking on stdin
# 1: Blocking on stdin
# 2: Not blocking on stdin but send %ping before reading next command.
READSTATE=0
#{SUB}
BASEID=str(random.randint(0, 1048576)) + str(os.getpid()) + str(int(time.time() * 1000000))
IDCOUNT=0

def squash(i):
    a = list(map(chr, list(range(48,58))+list(range(65,91))+list(range(97,123))))
    b = len(a)
    return a[i] if i < b else squash(i // b) + a[i % b]

def makeid():
    global IDCOUNT
    result = BASEID + str(IDCOUNT)
    IDCOUNT += 1
    return squash(int(result))

def log(message):
    if VERBOSE:
        global LOGFILE
        if not LOGFILE:
            LOGFILE = open("/tmp/framer.txt", "a")
        print(f'DEBUG {os.getpid()}: {message}', file=LOGFILE)
        LOGFILE.flush()

def send(data):
    if QUITTING:
        log("[squelched] " + str(data))
        return
    log("> " + str(data))
    os.write(sys.stdout.fileno(), data)

def send_esc(text):
    if QUITTING:
        log("[squelched] " + str(text))
        return
    log("> [osc 134] " + str(text) + " [st]")
    print('\033]134;:' + str(text) + '\033\\', end="")
    sys.stdout.flush()

class Process:
    @staticmethod
    async def run_tty(executable, args, cwd, env):
        master, slave = pty.openpty()
        try:
            def set_ctty(ctty_fd, master_fd):
                os.setsid()
                os.close(master_fd)
                fcntl.ioctl(ctty_fd, termios.TIOCSCTTY, 0)
                window_size = fcntl.ioctl(sys.stdin.fileno(), termios.TIOCGWINSZ, '00000000')
                fcntl.ioctl(ctty_fd, termios.TIOCSWINSZ, window_size)
            log(env)
            log(f'create subprocess args={args} cwd={cwd} executable={executable}')
            proc = await asyncio.create_subprocess_exec(
                *args,
                stdin=slave,
                stdout=slave,
                stderr=slave,
                cwd=cwd,
                env=env,
                executable=executable,
                preexec_fn=lambda: set_ctty(slave, master))
        finally:
            os.close(slave)
        return await Process.run_tty_proc(proc, master, f'run_tty({args})')

    @staticmethod
    async def run_shell_tty(command):
        master, slave = pty.openpty()
        try:
            env = dict(os.environ)
            env["LANG"] = "C"
            proc = await asyncio.create_subprocess_shell(
                command,
                stdin=slave,
                stdout=slave,
                stderr=slave,
                env=env)
        finally:
            os.close(slave)
        return await Process.run_tty_proc(proc, master, f'run_shell_tty({command})')

    @staticmethod
    async def run_tty_proc(proc, master, descr):
        pipe = open(master, 'wb', 0)
        writer = await Process._writer(pipe)
        reader, _ = await Process._reader(pipe)
        process = Process(proc, writer, reader, None, master=master, descr=descr)
        # No need to close reader's transport because it's the same file descriptor as master.
        return process

    @staticmethod
    async def writer(fd):
        pipe = open(fd, 'wb', 0)

        return await Process._writer(pipe)

    @staticmethod
    async def _writer(pipe):
        loop = asyncio.get_event_loop()
        transport, protocol = await loop.connect_write_pipe(asyncio.Protocol, pipe)
        writer = asyncio.StreamWriter(
                transport=transport,
                protocol=protocol,
                reader=None,
                loop=loop)
        return writer

    @staticmethod
    async def reader(fd):
        pipe = open(fd, 'rb', 0)
        return Process._reader(pipe)

    @staticmethod
    async def _reader(pipe):
        loop = asyncio.get_event_loop()
        reader = asyncio.StreamReader()
        protocol = asyncio.StreamReaderProtocol(reader)
        transport, _ = await loop.connect_read_pipe(lambda: protocol, pipe)
        return reader, transport

    def __init__(self, process, writer, stdout_reader, stderr_reader, master=None, descr=""):
        self.__process = process
        self.__writer = writer
        self.__stdout_reader = stdout_reader
        self.__stderr_reader = stderr_reader
        self.__stdout_read_handler = None
        self.__stderr_read_handler = None
        self.__cleanup = []
        self.__return_code = None
        self.__master = master
        self.__descr = descr
        self.login = False

    @property
    def master(self):
        return self.__master

    async def cleanup(self):
        log(f'cleanup {self.__descr}: cleanup process {self.pid}')
        if self.__return_code is None:
            log(f'kill {self.__descr}')
            try:
                await self.kill(signal.SIGKILL)
            except Exception as e:
                log(f'cleanup {self.__descr}: exception {e} during kill')
            log(f'cleanup {self.__descr}: wait')
            await self.wait()
        log(f'cleanup {self.__descr}: close writer tx')
        self.__writer.transport.close()
        log(f'cleanup {self.__descr}: adding handlers to TASKS')
        global TASKS
        if self.__stderr_read_handler:
            TASKS.append(self.__stderr_read_handler)
        TASKS.append(self.__stdout_read_handler)
        log(f'cleanup {self.__descr}: running cleanup callbacks')

        # StreamReader doesn't have a transport so it must be closed by a __cleanup function.
        for f in self.__cleanup:
            f()
        log(f'cleanup {self.__descr}: done')

    def add_cleanup(self, coro):
        self.__cleanup.append(coro)

    async def kill(self, signal):
        self.__process.send_signal(signal)

    async def wait(self):
        rc = await self.__process.wait()
        self.__return_code = rc
        return rc

    @property
    def return_code(self):
        return self.__return_code

    @property
    def pid(self):
        return self.__process.pid

    async def readline(self):
        return await self.__stdout_reader.readline()

    async def read_forever(self, reader, channel, callback):
        try:
            while True:
                log(f'read_forever {self.__descr}: reading for channel {channel}')
                value = await reader.read(256)
                log(f'read_forever {self.__descr}: read {value} for channel {channel}')
                coro = callback(channel, value)
                if coro:
                    log(f'read_forever {self.__descr}: await callback-returned coro {coro}')
                    await coro
                if len(value) == 0:
                    return
        except IOError:
            log(f'read_forever {self.__descr}: stopping because of IOError')
            coro = callback(channel, b'')
            await coro
            return
        except Exception as e:
            log(f'read_forever {self.__descr}: {e}')

    async def handle_read(self, callback):
        self.__stdout_read_handler = asyncio.create_task(self.read_forever(self.__stdout_reader, 1, callback))
        if self.__stderr_reader:
            self.__stderr_read_handler = asyncio.create_task(self.read_forever(self.__stderr_reader, 2, callback))

    async def write(self, data):
        self.__writer.write(data)

    def send_signal(self, signal):
        self.__process.send_signal(signal)

## Login Shell

def guess_login_shell():
    path = pwd.getpwuid(os.geteuid()).pw_shell
    if os.access(path, os.X_OK):
        return path
    return "/bin/sh"

## Process monitoring

async def autopoll(delay):
    try:
        global AUTOPOLL
        while True:
            log('autopoll: call poll()')
            output = await poll()
            if not len(output):
                log(f'autopoll: sleep for {delay}')
                await asyncio.sleep(delay)
                log(f'autopoll: awoke')
                continue
            # Send poll output and sleep until client requests autopolling again.
            identifier = makeid()
            send_esc(f'%autopoll {identifier}')
            for line in output:
                send(line.encode("utf-8") + b'\n')
            send_esc(f'%end {identifier}')
            AUTOPOLL = 0
            while not AUTOPOLL:
                log(f'autopoll: sleep for {delay}')
                await asyncio.sleep(delay)
                log(f'autopoll: awoke')
    except asyncio.CancelledError:
        log('autopoll canceled')
        raise
    except Exception as e:
        log(f'autopoll threw {e}: {traceback.format_exc()}')

async def poll():
    env = dict(os.environ)
    env["LANG"] = "C"
    proc = await asyncio.create_subprocess_shell(
        "ps -eo pid,ppid,stat,lstart,command",
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env=env)
    log(f'poll: run ps {proc}')
    output, erroutput = await proc.communicate()
    if proc.returncode == 0:
        log(f'poll: successful return')
        final = procmon_parse(output)
        log(f'poll: return parsed output')
        return final
    log(f'poll: ps failed with {proc.returncode}')
    return None

async def register(pid):
    global REGISTERED
    if pid in REGISTERED:
        return
    REGISTERED.append(pid)
    log(f'After registering {pid} REGISTERED={REGISTERED}')

async def deregister(pid):
    global REGISTERED
    if pid in REGISTERED:
        REGISTERED.remove(pid)

def procmon_parse(output):
    output = output.decode("utf-8")
    lines = output.split("\n")
    whitespace = r'\s+'
    number = r'\d+'
    nonspace = r'\S+'
    letters = r'[A-Za-z]+'
    pattern = "".join(
        [r'^',
         r'\s*',
         r'(',
         number,  # pid [capture 1]
         r')',
         whitespace,
         r'(',
         number,  # ppid [capture 2]
         r')',
         whitespace,
         r'(',
         nonspace,  # stat [capture 3]
         r')',
         whitespace,
         r'(',
         letters,  # day of week  [capture 4]
         whitespace,
         letters,  # name of month
         whitespace,
         number,  # day of month
         whitespace,
         number,  # hh
         r':',
         number,  # mm
         r':',
         number,  # ss
         whitespace,
         number,  # yyyy
         r')',
         whitespace,
         r'(.*)'  # command  [capture 5]
    ])
    def parse(line):
        match = re.search(pattern, line)
        if not match:
            return None
        return (match.group(1), match.group(2), match.group(3), match.group(4), match.group(5))
    rows = map(parse, lines)
    # pid->ppid
    parent={}
    # ppid->[pid]
    children={}
    # pid->row
    index={}
    for row in rows:
        if row is None:
            continue
        if row[4].startswith("(") and row[4].endswith(")"):
            log(f'procmon_parse: ignore defunct {row}')
            continue
        pid = row[0]
        ppid = row[1]
        parent[pid] = ppid
        children[ppid] = children.get(ppid, []) + [pid]
        index[pid] = row
    log(f'procmon_parse: {len(index)} valid rows')
    # pid -> row
    results = {}
    def add(pid):
        results[pid] = index[pid]
        for child in children.get(pid, []):
            add(child)
    for pid in REGISTERED:
        log(f'procmon_parse: Add hierarchy starting at {pid}')
        if str(pid) in index:
            add(str(pid))
    log(f'procmon_parse: {len(results)} processes in output')

    global LASTPS
    last = dict(LASTPS)
    LASTPS = dict(results)

    def diff():
        currentkeys = set(results.keys())
        lastkeys = set(last.keys())
        log(f'procmon_parse: diff current={currentkeys} last={lastkeys}')
        for addition in currentkeys - lastkeys:
            log(f'procmon_parse: add {addition}')
            yield "+" + " ".join(map(str, results[addition]))
        for removal in lastkeys - currentkeys:
            log(f'procmon_parse: remove {removal}')
            yield "-" + str(removal)
        for pid in results:
            if pid in last and results[pid] != last[pid]:
                log(f'procmon_parse: edit {pid}')
                yield "~" + " ".join(map(str, results[pid]))
    return list(diff())


## Commands

async def handle_login(identifier, args):
    log("begin handle_login")
    cwd = args[0]
    args = args[1:]
    log(f'cwd={cwd} args={args}')
    cwd = os.path.expandvars(os.path.expanduser(cwd))
    had_args = len(args) > 0
    guessed = guess_login_shell()
    if args:
        login_shell = args[0]
        del args[0]
        argv0 = login_shell
    else:
        login_shell = guessed
    if login_shell == guessed:
        _, shell_name = os.path.split(login_shell)
        argv0 = "-" + shell_name

    log(f'Login shell is {login_shell}. Guessed shell is {guessed}. argv0 is {argv0}')
    try:
        proc = await Process.run_tty(
            login_shell,
            [argv0] + args,
            cwd,
            os.environ)
        log("login shell started")
        global PROCESSES
        proc.login = True
        PROCESSES[proc.pid] = proc
        begin(identifier)
        send_esc(proc.pid)
        end(identifier, 0)
        await proc.handle_read(make_monitor_process(proc, True))
    except Exception as e:
        log(f'handle_login: {e}')
        begin(identifier)
        send_esc(f'Command failed: {e}')
        end(identifier, 1)
    return False

async def handle_run(identifier, args):
    """Run a command inside the user's shell"""
    try:
        proc = await Process.run_shell_tty(args[0])
        global PROCESSES
        PROCESSES[proc.pid] = proc
        begin(identifier)
        send_esc(proc.pid)
        end(identifier, 0)
        await proc.handle_read(make_monitor_process(proc, False))
    except Exception as e:
        log(f'handle_run: {e}')
        begin(identifier)
        end(identifier, 1)
    return False

def reset():
    global REGISTERED
    global LASTPS
    global AUTOPOLL
    REGISTERED = []
    LASTPS = {}
    AUTOPOLL = 0

async def handle_reset(identifier, args):
    reset()
    begin(identifier)
    end(identifier, 0)

async def handle_save(identifier, args):
    log(f'handle_save {identifier} {args}')
    global RECOVERY_STATE
    try:
        RECOVERY_STATE = dict(s.split('=', 1) for s in args)
        code = 0
    except Exception as e:
        log(f'handle_save: {e}')
        code = 1
    begin(identifier)
    end(identifier, code)

async def handle_file(identifier, args):
    log(f'handle_ls {identifier} {args}')
    if len(args) < 2:
        begin(identifier)
        end(identifier, 1)
        return
    begin(identifier)
    if args[0] == "ls":
        await handle_file_ls(identifier, base64.b64decode(args[1]).decode('latin1'), args[2])
        return
    if args[0] == "fetch":
        await handle_file_fetch(identifier, base64.b64decode(args[1]).decode('latin1'))
        return
    if args[0] == "stat":
        await handle_file_stat(identifier, base64.b64decode(args[1]).decode('latin1'))
        return
    log(f'unrecognized subcommand args[0]')
    end(identifier, 1)

def permissions(path):
    return {
        "r": os.access(path, os.R_OK, effective_ids=True),
        "w": os.access(path, os.W_OK, effective_ids=True),
        "x": os.access(path, os.X_OK, effective_ids=True) }

def remotefile(pp, abspath, s):
    if stat.S_ISLNK(s.st_mode):
        k = {"symlink": {"_0": os.readlink(abspath) }}
    elif stat.S_ISDIR(s.st_mode):
        k = {"folder": {}}
    elif stat.S_ISREG(s.st_mode):
        k = {"file": {"_0": {"size": s[stat.ST_SIZE]}}}
    else:
        return None
    to = 978307200
    ctime = s[stat.ST_CTIME] - to
    mtime = s[stat.ST_MTIME] - to
    return {"absolutePath": abspath,
            "kind": k,
            "permissions": permissions(abspath),
            "parentPermissions": pp,
            "ctime": ctime,
            "mtime": mtime}

def file_error(identifier, e, path):
    try:
        raise e
    except OSError as e:
        log(f'file_error {path}: {traceback.format_exc()}')
        errors = {errno.EPERM: 1, errno.ENOENT: 2, errno.ENOTDIR: 3, errno.ELOOP: 4}
        end(identifier, errors.get(e.errno, 100))
    except PermissionError as e:
        log(f'file_error {path}: {traceback.format_exc()}')
        end(identifier, 1)
    except Exception as e:
        log(f'file_error {path}: {traceback.format_exc()}')
        end(identifier, 255)

async def handle_file_ls(identifier, path, sorting):
    log(f'handle_file_ls {identifier} {path}')
    try:
        pp = permissions(path)
        files = [(os.path.join(path, f),
                  os.stat(os.path.join(path, f), follow_symlinks=False))
                  for f in os.listdir(path)]
        def fmt(t):
            return remotefile(pp, t[0], t[1])

        obj = list(filter(lambda x: x is not None, map(fmt, files)))
        def sort_ls(d):
            if sorting == 'n':
                return d['absolutePath']
            return d['mtime']
        obj = sorted(obj, key=sort_ls)
        log(f'After sorting contents of {path} are {obj}')
        send_esc("[")
        first = True
        for entry in obj:
            if first:
                first = False
            else:
                send_esc(",")
            j = json.dumps(entry)
            send_esc(j)
        send_esc("]")
        end(identifier, 0)
        log("handle_file_ls completed normally")
    except Exception as e:
        file_error(identifier, e, path)

async def handle_file_stat(identifier, path):
    log(f'handle_file_stat {identifier} {path}')
    try:
        pp = permissions(os.path.abspath(os.path.join(path, os.pardir)))
        s = os.stat(path, follow_symlinks=False)
        obj = remotefile(pp, path, s)
        j = json.dumps(obj)
        send_esc(j)
        end(identifier, 0)
    except Exception as e:
        file_error(identifier, e, path)

async def handle_file_fetch(identifier, path):
    log(f'handle_file_fetch {identifier} {path}')
    try:
        with open(path, "rb") as f:
            content = f.read()
            log(type(content))
            encoded = base64.encodebytes(content).decode('utf8')
            for line in encoded.split("\n"):
                log(f'will send f{type(line)}')
                send_esc(line)
        log("ending")
        end(identifier, 0)
    except Exception as e:
        file_error(identifier, e, path)


async def handle_recover(identifier, args):
    log("handle_recover")
    reset()
    send_esc(f'begin-recovery')
    for pid in PROCESSES:
        proc = PROCESSES[pid]
        if proc.login:
            send_esc(f'recovery: login {pid}')
            for key in RECOVERY_STATE:
                send_esc(f'recovery: {key} {RECOVERY_STATE[key]}')
        else:
            send_esc(f'recovery: process {pid}')
    send_esc(f'end-recovery')

async def handle_register(identifier, args):
    if len(args) < 1:
        fail(identifier, "not enough arguments")
        return
    try:
        pid = int(args[0])
    except Exception as e:
        log(f'handle_register: {e}')
        fail(identifier, "exception decoding argument")
        return
    begin(identifier)
    end(identifier, 0)
    await register(pid)

async def handle_deregister(identifier, args):
    if len(args) < 1:
        fail(identifier, "not enough arguments")
        return
    try:
        pid = int(args[0])
    except Exception as e:
        log(f'handle_deregister: {e}')
        fail(identifier, "exception decoding argument")
        return
    begin(identifier)
    end(identifier, 0)
    await deregister(pid)

async def handle_autopoll(identifier, args):
    log(f'handle_autopoll({identifier}, {args})')
    begin(identifier)
    end(identifier, 0)
    global AUTOPOLL
    if AUTOPOLL:
        return
    AUTOPOLL = 1

    global AUTOPOLL_TASK
    if AUTOPOLL_TASK is not None:
        return
    AUTOPOLL_TASK = asyncio.create_task(autopoll(1.0))


async def handle_poll(identifier, args):
    log(f'handle_poll({identifier}, {args})')
    output = await poll()
    log(f'handle_poll({identifier}, {args}): read {len(output)} bytes of output')
    begin(identifier)
    if output is not None:
        for line in output:
            send_esc(line)
        end(identifier, 0)
    else:
        end(identifier, 1)

async def handle_send(identifier, args):
    if len(args) < 2:
        fail(identifier, "not enough arguments")
        return
    try:
        pid = int(args[0])
        decoded = base64.b64decode(args[1])
    except Exception as e:
        log(f'handle_send: {e}')
        fail(identifier, "exception decoding argument")
        return
    if pid not in PROCESSES:
        log("No such process")
        begin(identifier)
        end(identifier, 1)
        return
    proc = PROCESSES[pid]
    log(f'write {decoded}')
    await proc.write(decoded)
    log('wrote')
    begin(identifier)
    end(identifier, 0)
    return False

async def handle_kill(identifier, args):
    log(f'kill {args}')
    try:
        pid = int(args[0])
    except:
        fail(identifier, "pid not an int")
        return
    if pid not in PROCESSES:
        log(f'no such process')
        begin(identifier)
        error(identifier, 1)
        return
    proc = PROCESSES[int(args[0])]
    proc.send_signal(signal.SIGTERM)
    begin(identifier)
    end(identifier, 0)
    return False

async def handle_quit(identifier, args):
    begin(identifier)
    end(identifier, 0)
    global AUTOPOLL_TASK
    if AUTOPOLL_TASK:
        log('will cancel autopoll')
        AUTOPOLL_TASK.cancel()
        try:
            log('await canceled autopoll task')
            await AUTOPOLL_TASK
        except asyncio.CancelledError:
            log('autopoll is now canceled')
        AUTOPOLL_TASK = None
    return True

## Helpers for run()

async def start_process(args):
    runid = makeid()
    PROCESSES[runid] = proc
    return runid

def make_monitor_process(proc, islogin):
    def monitor_process(channel, value):
        log(f'monitor_process called with channel={channel} islogin={islogin} value={value}')
        if len(value) == 0:
            global COMPLETED
            log(f'add {proc.pid} to list of completed PIDs')
            COMPLETED.append(proc.pid)
            return cleanup()
        print_output(makeid(), proc.pid, channel, islogin, value)
        return None
    return monitor_process

def print_output(identifier, pid, channel, islogin, data):
    if islogin:
        send_esc(f'%output {identifier} {pid} -1 {DEPTH}')
    else:
        send_esc(f'%output {identifier} {pid} {channel} {DEPTH}')
    send(data)
    send_esc(f'%end {identifier}')

## Infra

def fail(identifier, reason):
    log(f'fail: {reason}')
    begin(identifier)
    end(identifier, 1)

def begin(identifier):
    send_esc(f'begin {identifier}')

def end(identifier, status):
    if len(PROCESSES):
        type = "f"
    else:
        type = "r"
    send_esc(f'end {identifier} {status} {type}')

async def cleanup():
    """Await tasks that have completed, clear the COMPLETED list, and remove them from TASKS."""
    log("cleaning up")
    global COMPLETED
    completed = list(COMPLETED)
    COMPLETED = []
    for pid in completed:
        if pid not in PROCESSES:
            log(f'pid {pid} no longer in PROCESSES, not cleaning up')
            continue
        log(f'clean up pid {pid}')
        proc = PROCESSES[pid]
        del PROCESSES[pid]
        await proc.cleanup()
        send_esc(f'%terminate {proc.pid} {proc.return_code}')

async def handle(args):
    log(f'handle {args}')
    if len(args) == 0:
        # During recovery a blank line is sent. Just ignore it to avoid getting out of sync.
        return False
    cmd = args[0]
    del args[0]
    identifier = makeid()
    if cmd not in HANDLERS:
        fail(identifier, "unrecognized command")
        return

    f = HANDLERS[cmd]
    log(f'handler is {f}')
    should_quit = False
    try:
        should_quit = await f(identifier, args)
        if should_quit:
            global QUITTING
            QUITTING=True
    except Exception as e:
        log(f'Handler for {cmd} threw {e}: {traceback.format_exc()}')
    log("call cleanup()")
    await cleanup()

    global TASKS
    log(f'awaiting {TASKS}')
    while TASKS:
        task = TASKS[0]
        del TASKS[0]
        log(f'await {task}')
        await task
    TASKS=[]

    return should_quit

def read_line():
    try:
        log("Calling sys.stdin.readline")
        return sys.stdin.readline().rstrip('\n')
    except:
        log("Caught exception")
        sys.exit(1)

async def mainloop():
    global RUNLOOP
    global READSTATE
    RUNLOOP = asyncio.get_event_loop()
    args = []
    while True:
        log("reading")
        try:
            if READSTATE == 2:
                log('mainloop: send deferred ping')
                # It's safe to ping because we haven't sent a begin yet.
                ping()
            READSTATE = 1
            line = await asyncio.get_event_loop().run_in_executor(None, read_line)
        except:
            fail("none", "exception during read_line")
            return 0
        READSDTATE = 0
        log(f'read from stdin "{line}" with length {len(line)}')
        if len(line):
            if len(args) and args[-1].endswith("\\"):
                args[-1] = args[-1][:-1] + line
            else:
                args.append(line)
            log(f'args is now {args}')
        else:
            quit = await handle(args)
            log("flush stdout")
            sys.stdout.flush()
            if quit:
                log("Mainloop returns 0")
                return 0
            args = []

def ping():
    if len(PROCESSES):
        send_esc("%ping")
    else:
        log("Squelch pre-login ping")

async def update_pty_size():
    log(f'update_pty_size')
    window_size = fcntl.ioctl(sys.stdin.fileno(), termios.TIOCGWINSZ, '00000000')
    for pid in PROCESSES:
        proc = PROCESSES[pid]
        master = proc.master
        if master is not None:
            log(f'TIOCSWINSZ {proc}')
            # TODO: This is wrong becuse it could happen while awaiting something else between begin and end.
            fcntl.ioctl(master, termios.TIOCSWINSZ, window_size)
        else:
            log(f'no master fd for {proc}')

def on_sigwinch(_sig, _stack):
    log(f'Received SIGWINCH')
    if RUNLOOP is None:
        # There may not be an event loop yet.
        log('Ignore because no runloop')
        return
    global READSTATE
    if READSTATE == 1:
        log("send ping while blocked on stdin")
        ping()
    else:
        READSTATE = 2
    asyncio.run_coroutine_threadsafe(update_pty_size(), RUNLOOP)

HANDLERS = {
    "run": handle_run,
    "login": handle_login,
    "send": handle_send,
    "kill": handle_kill,
    "quit": handle_quit,
    "register": handle_register,
    "deregister": handle_deregister,
    "poll": handle_poll,
    "reset": handle_reset,
    "autopoll": handle_autopoll,
    "recover": handle_recover,
    "save": handle_save,
    "file": handle_file,
}

def main():
    if sys.stdin.isatty():
        signal.signal(signal.SIGWINCH, on_sigwinch)
    asyncio.run(mainloop())

if __name__ == "__main__":
    main()
