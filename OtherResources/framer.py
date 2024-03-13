#!/usr/bin/env python3
import asyncio
import base64
import errno
import fcntl
import json
import os
import platform
import pty
import pwd
import random
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import termios
import time
import traceback
import zipfile

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
TTY_TASK = None
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
        print(f'DEBUG {time.time():.6f} {os.getpid()}: {message}', file=LOGFILE)
        LOGFILE.flush()

def send(q, data):
    if QUITTING:
        log("[squelched] " + str(data))
        return
    log("> " + str(data))
    q.append(data)

def send_esc(q, text):
    if QUITTING:
        log("[squelched] " + str(text))
        return
    log("> [osc 134] " + str(text) + " [st]")
    q.append('\033]134;:' + str(text) + '\033\\')

def lock():
    return []

def unlock(writes):
    if writes:
        for data in writes:
            if isinstance(data, str):
                data = data.encode('utf-8')
            os.write(sys.stdout.fileno(), data)
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
        self.echo = True
        self.icanon = True
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
            cats = await poll()
            if not cats:
                log(f'autopoll: sleep for {delay}')
                await asyncio.sleep(delay)
                log(f'autopoll: awoke')
                continue
            # Send poll output and sleep until client requests autopolling again.
            identifier = makeid()
            q = lock()
            send_esc(q, f'%autopoll {identifier}')
            send_poll_output(q, cats)
            send_esc(q, f'%end {identifier}')
            unlock(q)
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

def send_poll_output(q, cats):
    for catname in cats:
        output = cats[catname]
        send(q, f'$begin {catname}'.encode("utf-8") + b'\n')
        for line in output:
            send(q, line.encode("utf-8") + b'\n')

def get_echo_icanon(tty):
    try:
        attrs = termios.tcgetattr(tty)
        return (bool(attrs[3] & termios.ECHO), bool(attrs[3] & termios.ICANON))
    except Exception as e:
        log(f'get_echo_icanon threw {e}: {traceback.format_exc()}')
        raise

async def watch_tty(proc, delay):
    try:
        while True:
            log("watch_tty: poll")
            poll_tty(proc)
            await asyncio.sleep(delay)
    except asyncio.CancelledError:
        log('watch_tty canceled')
        raise
    except Exception as e:
        log(f'watch_tty threw {e}: {traceback.format_exc()}')

def poll_tty(proc):
    log(f"Check TTY with fd {proc.master}")
    new_echo, new_icanon = get_echo_icanon(proc.master)
    if new_echo != proc.echo or new_icanon != proc.icanon:
        log(f'echo: {proc.echo}->{new_echo}, icanon: {proc.icanon}->{new_icanon}')
        parts = [
            ('+' if new_echo else '-') + 'echo',
            ('+' if new_icanon else '-') + 'icanon']
        print_tty(" ".join(parts))
    proc.echo = new_echo
    proc.icanon = new_icanon

async def poll():
    result = {}
    ps_out = await poll_ps()
    if ps_out is not None:
        result["ps"] = ps_out
    cpu_time_diff = await poll_cpu()
    if cpu_time_diff is not None:
        result["cpu"] = cpu_time_diff
    return result

mpstat_exists = None  # Global variable to cache the mpstat existence check

async def check_mpstat_exists():
    global mpstat_exists
    if mpstat_exists is None:
        try:
            log("Checking if mpstat exists")
            proc = await asyncio.create_subprocess_shell(
                "mpstat -V",
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            output, _ = await proc.communicate()
            log(f'return code is {proc.returncode}')
            mpstat_exists = proc.returncode == 0
        except FileNotFoundError:
            log("mpstat: file not found")
            mpstat_exists = False


async def poll_cpu():
    operating_system = platform.system()
    if operating_system == 'Darwin':  # macOS
        command = "top -l 1 -n 0 | awk '/CPU usage/ {print $3}'"
    elif operating_system == 'Linux':  # Linux
        await check_mpstat_exists()
        if not mpstat_exists:
            return None
        command = "mpstat -P ALL 1 1 | awk '/Average:/ && $2 == \"all\" {print 100 - $NF}'"
    else:
        return None
    env = dict(os.environ)
    env["LANG"] = "C"
    proc = await asyncio.create_subprocess_shell(
        command,
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env=env)
    log(f'poll_cpu: run {command} {proc}')
    output, erroutput = await proc.communicate()
    if proc.returncode == 0:
        log(f'poll_cpu: successful return')
        # Parse the output here
        final = "=" + output.decode("utf-8").strip()
        log(f'poll_cpu: return parsed output')
        return [final]
    log(f'poll_cpu: {command} failed with {proc.returncode}')
    return None

async def poll_ps():
    env = dict(os.environ)
    env["LANG"] = "C"
    proc = await asyncio.create_subprocess_shell(
        "ps -eo pid,ppid,stat,lstart,command",
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env=env)
    log(f'poll_ps: run ps {proc}')
    output, erroutput = await proc.communicate()
    if proc.returncode == 0:
        log(f'poll_ps: successful return')
        final = procmon_parse(output)
        log(f'poll_ps: return parsed output')
        return final
    log(f'poll_ps: ps failed with {proc.returncode}')
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


async def save_and_exec(identifier, code):
    log("begin save_and_exec")
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False)
        tmpname = tmp.name
        log(f'save_and_exec: tmp={tmpname}')
        tmp.write(code.encode("utf-8"))
        tmp.close()
        st = os.stat(tmpname)
        os.chmod(tmpname, st.st_mode | stat.S_IEXEC)

        e = dict(os.environ)
        e["SELF"] = tmpname
        await run_login_shell(identifier, "/bin/sh", ["sh", tmpname], os.getcwd(), e)
    except Exception as e:
        log(f'save_and_exec: {traceback.format_exc()}')
        q = begin(identifier)
        send_esc(q, f'Command failed: {e}')
        end(q, identifier, 1)

## Commands

async def handle_login(identifier, args):
    log("begin handle_login")
    cwd = args[0]
    args = args[1:]
    log(f'cwd={cwd} args={args}')
    cwd = os.path.expandvars(os.path.expanduser(cwd))
    had_args = len(args) > 0
    if args:
        args = ["-c", " ".join(args)]
        log(f'Update args to {args}')
    login_shell = guess_login_shell()
    _, shell_name = os.path.split(login_shell)
    argv0 = "-" + shell_name

    return await run_login_shell(identifier, login_shell, [argv0] + args, cwd, os.environ)

async def run_login_shell(identifier, login_shell, argv, directory, environment):
    log(f'run_login_shell: dir={directory} command={login_shell} argv={argv}')
    try:
        proc = await Process.run_tty(
            login_shell,
            argv,
            directory,
            environment)
        log("login shell started")
        global PROCESSES
        proc.login = True
        PROCESSES[proc.pid] = proc
        q = begin(identifier)
        send_esc(q, proc.pid)
        end(q, identifier, 0)
        await proc.handle_read(make_monitor_process(proc, True))
    except Exception as e:
        log(f'run_login_shell: {e}')
        q = begin(identifier)
        send_esc(q, f'Command failed: {e}')
        end(q, identifier, 1)
    return False

async def handle_run(identifier, args):
    """Run a command inside the user's shell"""
    try:
        proc = await Process.run_shell_tty(args[0])
        global PROCESSES
        PROCESSES[proc.pid] = proc
        q = begin(identifier)
        send_esc(q, proc.pid)
        end(q, identifier, 0)
        await proc.handle_read(make_monitor_process(proc, False))

        start_tty_task(identifier, proc)
    except Exception as e:
        log(f'handle_run: {e}')
        q = begin(identifier)
        end(q, identifier, 1)
    return False

def start_tty_task(identifier, proc):
    proc.tty_task = asyncio.create_task(watch_tty(proc, 1))

def reset():
    global REGISTERED
    global LASTPS
    global AUTOPOLL
    REGISTERED = []
    LASTPS = {}
    AUTOPOLL = 0

async def handle_reset(identifier, args):
    reset()
    q = begin(identifier)
    end(q, identifier, 0)

async def handle_save(identifier, args):
    log(f'handle_save {identifier} {args}')
    global RECOVERY_STATE
    try:
        RECOVERY_STATE = dict(s.split('=', 1) for s in args)
        code = 0
    except Exception as e:
        log(f'handle_save: {e}')
        code = 1
    q = begin(identifier)
    end(q, identifier, code)

async def handle_eval(identifier, args):
    log(f'handle_eval {identifier} [{len(args[0])} bytes]')
    await save_and_exec(identifier, base64.b64decode(args[0]).decode('latin1'))

async def handle_file(identifier, args):
    log(f'handle_file {identifier} {args}')
    if len(args) < 2:
        q = begin(identifier)
        end(q, identifier, 1)
        return
    q = begin(identifier)
    sub = args[0]
    if sub == "ls":
        await handle_file_ls(q, identifier, base64.b64decode(args[1]).decode('latin1'), args[2])
        return
    if sub == "fetch":
        if len(args) >= 4:
            await handle_file_fetch(q, identifier, base64.b64decode(args[1]).decode('latin1'), int(args[2]), int(args[3]))
        else:
            await handle_file_fetch(q, identifier, base64.b64decode(args[1]).decode('latin1'), 0, float('inf'))
        return
    if sub == "stat":
        await handle_file_stat(q, identifier, base64.b64decode(args[1]).decode('latin1'))
        return
    if sub == "suggest":
        await handle_file_suggest(q,
                                  identifier,
                                  base64.b64decode(args[1]).decode('latin1'),
                                  args[2],
                                  base64.b64decode(args[3]).decode('latin1'),
                                  args[4],
                                  int(args[5]))
        return
    if sub == "rm":
        i = 1
        recursive = False
        while i < len(args) and args[i].startswith("-"):
            if args[i] == "-r":
                recursive = True
            i += 1
        if i == len(args):
            end(q, identifier, 1)
            return
        await handle_file_rm(q, identifier, base64.b64decode(args[i]).decode('latin1'), recursive)
        return
    if sub == "ln":
        await handle_file_ln(
            q,
            identifier,
            base64.b64decode(args[1]).decode('latin1'),
            base64.b64decode(args[2]).decode('latin1'))
        return
    if sub == "mv":
        await handle_file_mv(
            q,
            identifier,
            base64.b64decode(args[1]).decode('latin1'),
            base64.b64decode(args[2]).decode('latin1'))
        return
    if sub == "mkdir":
        await handle_file_mkdir(q, identifier, base64.b64decode(args[1]).decode('latin1'))
        return
    if sub == "create":
        await handle_file_create(q,
                                 identifier,
                                 base64.b64decode(args[1]).decode('latin1'),
                                 base64.b64decode("".join(args[2:])))
        return
    if sub == "append":
        await handle_file_append(q,
                                 identifier,
                                 base64.b64decode(args[1]).decode('latin1'),
                                 base64.b64decode("".join(args[2:])))
        return
    if sub == "utime":
        await handle_file_utime(q,
                                identifier,
                                base64.b64decode(args[1]).decode('latin1'),
                                int(float(args[2])))
        return
    if sub == "chmod-u":
        await handle_file_chmod_u(q,
                                  identifier,
                                  base64.b64decode(args[1]).decode('latin1'),
                                  args[2])
        return
    if sub == "zip":
        await handle_file_zip(q,
                              identifier,
                              base64.b64decode(args[1]).decode('latin1'))
        return
    log(f'unrecognized subcommand {sub}')
    end(q, identifier, 1)

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

def file_error(q, identifier, e, path):
    if e is None:
        log(f'file_error {path}')
        end(q, identifier, 1)
        return
    try:
        raise e
    except OSError as e:
        log(f'file_error {path}: {traceback.format_exc()}')
        errors = {errno.EPERM: 1, errno.ENOENT: 2, errno.ENOTDIR: 3, errno.ELOOP: 4}
        end(q, identifier, errors.get(e.errno, 100))
    except PermissionError as e:
        log(f'file_error {path}: {traceback.format_exc()}')
        end(q, identifier, 1)
    except Exception as e:
        log(f'file_error {path}: {traceback.format_exc()}')
        end(q, identifier, 255)

async def handle_file_ls(q, identifier, path, sorting):
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
        send_esc(q, "[")
        first = True
        for entry in obj:
            if first:
                first = False
            else:
                send_esc(q, ",")
            j = json.dumps(entry)
            send_esc(q, j)
        send_esc(q, "]")
        end(q, identifier, 0)
        log("handle_file_ls completed normally")
    except Exception as e:
        file_error(q, identifier, e, path)

def send_remote_file(q, path):
    pp = permissions(os.path.abspath(os.path.join(path, os.pardir)))
    s = os.stat(path, follow_symlinks=False)
    obj = remotefile(pp, path, s)
    j = json.dumps(obj)
    send_esc(q, j)

async def handle_file_stat(q, identifier, path):
    log(f'handle_file_stat {identifier} {path}')
    try:
        send_remote_file(q, path)
        end(q, identifier, 0)
    except Exception as e:
        file_error(q, identifier, e, path)

async def handle_file_suggest(q, identifier, prefix, directories, pwd, permissions, max_count):
    log(f'handle_file_suggest({identifier}, {prefix}, {directories}, {pwd}, {permissions})')
    combined = []
    for relative_directory in decode_base64_directories(directories):
        if relative_directory.startswith('/'):
            directory = relative_directory
        else:
            if not pwd:
                continue
            directory = os.path.join(pwd, relative_directory)
        temp = await really_find_completions_with_prefix(prefix, directory, max_count, 'x' in permissions)
        temp.sort()
        combined.extend([entry.removeprefix(prefix) for entry in temp])
        if len(combined) > max_count:
            break
    send_esc(q, json.dumps(combined))
    end(q, identifier, 0)

def decode_base64_directories(encoded_directories):
    decoded_directories = []
    directories = encoded_directories.split()

    for directory in directories:
        decoded_directory = base64.b64decode(directory).decode('utf-8')
        decoded_directories.append(decoded_directory)

    return decoded_directories

async def really_find_completions_with_prefix(prefix, directory, max_count, executable):
    log(f'really_find_completions_with_prefix({prefix}, {directory}, {max_count}, {executable}')
    if not prefix.startswith('/') and directory.startswith('/'):
        log('Prefix is relative and directory is absolute. Recurse.')
        temp = await really_find_completions_with_prefix(
            os.path.join(directory, prefix), '', max_count, executable)
        prefix_to_remove = directory if directory.endswith('/') else directory + '/'
        return [entry.removeprefix(prefix_to_remove) for entry in temp]

    if prefix.endswith('/'):
        log('Prefix ends in slash')
        return await contents_of_directory(prefix, '', executable, max_count)

    results = []
    is_directory = False
    exists = os.path.exists(prefix)
    if exists:
        is_directory = os.path.isdir(prefix)
        if is_directory:
            results.append(prefix + '/')

    container = os.path.dirname(prefix)
    if len(container) == 0:
        log(f"No dirname for {prefix}")
        return results

    log("Add contents of directory using prefix basename")
    results.extend(await contents_of_directory(container, os.path.basename(prefix), executable, max_count))
    return results

async def contents_of_directory(directory, prefix, executable, max_count):
    log(f'contents_of_directory({directory}, {prefix}, {executable}, {max_count}')
    try:
        relative = await asyncio.get_event_loop().run_in_executor(None, lambda: os.listdir(directory))
        result = []
        for path in relative:
            if len(result) >= max_count:
                break
            file_name = os.path.basename(path)
            if len(prefix) == 0 or file_name.startswith(prefix):
                full_path = os.path.join(directory, path)
                if not executable or os.access(full_path, os.X_OK):
                    result.append(full_path)
        return result
    except Exception as e:
        log(f'exception while getting contents of {directory}: {traceback.format_exc()}')
        return []

async def handle_file_zip(q, identifier, path):
    log(f'handle_file_zip {identifier} {path}')

    if not os.path.isdir(path):
        log(f'{path} is not a directory')
        file_error(q, identifier, None, f'{path} is not a directory')
        return
    try:
        # Create a temporary file in the user's home directory
        temp_file = tempfile.NamedTemporaryFile(dir=os.path.expanduser("~"), prefix=".", delete=False)
        log(f'zip to {temp_file}')
        ziph = zipfile.ZipFile(temp_file.name, 'w', zipfile.ZIP_DEFLATED)
        log('Opened zip for writing')
    except Exception as e:
        file_error(q, identifier, e, "While creating a temporary file under your home directory")
        return

    try:
        for root, dirs, files in os.walk(path):
            for file in files:
                try:
                    full_path = os.path.join(root, file)
                    log('add {full_path}')
                    ziph.write(full_path,
                               os.path.relpath(os.path.join(root, file),
                                               os.path.join(path, '..')))
                except Exception as e:
                    log(f'Failed to add {file}: {e}')
                    # zip as much as possible. Errors are just ignored, which isn't great.
                    pass
        log('Done zipping')
    except Exception as e:
        file_error(q, identifier, e, temp_file)
    finally:
        log('close zip')
        ziph.close()
        log('send tempfile name')
        send_esc(q, temp_file.name)
        end(q, identifier, 0)

async def handle_file_fetch(q, identifier, path, offset, size):
    log(f'handle_file_fetch {identifier} {path}')
    try:
        with open(path, "rb") as f:
            if offset > 0:
                f.seek(offset)
            if size == float('inf'):
                content = f.read()
            else:
                content = f.read(size)
            log(type(content))
            encoded = base64.encodebytes(content).decode('utf8')
            for line in encoded.split("\n"):
                log(f'will send f{type(line)}')
                send_esc(q, line)
        log("ending")
        end(q, identifier, 0)
    except Exception as e:
        file_error(q, identifier, e, path)

async def handle_file_rm(q, identifier, path, recursive):
    log(f'handle_file_rm {identifier} {path} {recursive}')
    try:
        if os.path.isdir(path):
            if recursive:
                shutil.rmtree(path)
            else:
                os.rmdir(path)
        else:
            os.unlink(path)
        log("ending")
        end(q, identifier, 0)
    except Exception as e:
        file_error(q, identifier, e, path)

async def handle_file_ln(q, identifier, pointTo, symlink):
    log(f'handle_file_ln {pointTo} {symlink}')
    try:
        os.symlink(pointTo, symlink)
        send_remote_file(q, symlink)
        end(q, identifier, 0)
    except Exception as e:
        file_error(q, identifier, e, symlink)

async def handle_file_mv(q, identifier, source, dest):
    log(f'handle_file_mv {source} {dest}')
    try:
        shutil.move(source, dest)
        send_remote_file(q, dest)
        end(q, identifier, 0)
    except Exception as e:
        file_error(q, identifier, e, source)

async def handle_file_mkdir(q, identifier, path):
    log(f'handle_file_mkdir {identifier} {path}')
    try:
        os.mkdir(path)
        end(q, identifier, 0)
    except Exception as e:
        file_error(q, identifier, e, path)

async def handle_file_create(q, identifier, path, content):
    log(f'handle_file_create {identifier} {path} length={len(content)} bytes')
    try:
        with open(path, "wb") as f:
            f.write(content)
        send_remote_file(q, path)
        end(q, identifier, 0)
    except Exception as e:
        file_error(identifier, e, path)

async def handle_file_append(q, identifier, path, content):
    log(f'handle_file_append {identifier} {path} length={len(content)} bytes')
    try:
        with open(path, "ab") as f:
            f.write(content)
        send_remote_file(q, path)
        end(q, identifier, 0)
    except Exception as e:
        file_error(q, identifier, e, path)

async def handle_file_utime(q, identifier, path, date):
    log(f'handle_file_utime {identifier} {path} {date}')
    try:
        os.utime(path, (date, date))
        send_remote_file(q, path)
        end(q, identifier, 0)
    except Exception as e:
        file_error(q, identifier, e, path)

async def handle_file_chmod_u(q, identifier, path, mode):
    log(f'handle_file_chmod_u {identifier} {path} {mode}')
    try:
        s = os.stat(path, follow_symlinks=False)
        value = s.st_mode & ~(stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)
        if "r" in mode:
            value |= stat.S_IRUSR
        if "w" in mode:
            value |= stat.S_IWUSR
        if "x" in mode:
            value |= stat.S_IXUSR
        os.chmod(path, value)
        send_remote_file(q, path)
        end(q, identifier, 0)
    except Exception as e:
        file_error(q, identifier, e, path)

async def handle_recover(identifier, args):
    log("handle_recover")
    q = lock()
    reset()
    send_esc(q, f'begin-recovery')
    for pid in PROCESSES:
        proc = PROCESSES[pid]
        if proc.login:
            send_esc(q, f'recovery: login {pid}')
            for key in RECOVERY_STATE:
                send_esc(q, f'recovery: {key} {RECOVERY_STATE[key]}')
        else:
            send_esc(q, f'recovery: process {pid}')
    send_esc(q, f'end-recovery')
    unlock(q)

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
    q = begin(identifier)
    end(q,identifier, 0)
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
    q = begin(identifier)
    end(q,identifier, 0)
    await deregister(pid)

async def handle_autopoll(identifier, args):
    log(f'handle_autopoll({identifier}, {args})')
    q = begin(identifier)
    end(q,identifier, 0)
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
    log(f'handle_poll({identifier}, {args}): read {len(output)} categories of output')
    q = begin(identifier)
    if output is not None:
        send_poll_output(q,output)
        end(q,identifier, 0)
    else:
        end(q,identifier, 1)

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
        q = begin(identifier)
        end(q,identifier, 1)
        return
    proc = PROCESSES[pid]
    log(f'write {decoded}')
    await proc.write(decoded)
    log('wrote')
    q = begin(identifier)
    end(q,identifier, 0)
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
        q = begin(identifier)
        end(q,identifier, 1)
        return
    proc = PROCESSES[int(args[0])]
    proc.send_signal(signal.SIGTERM)
    q = begin(identifier)
    end(q,identifier, 0)
    return False

async def handle_quit(identifier, args):
    q = begin(identifier)
    end(q,identifier, 0)
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
        log("make_monitor_process: poll")
        try:
            poll_tty(proc)
        except Exception as e:
            log(f'make_monitor_process->poll_tty threw {e}: {traceback.format_exc()}')
        return None
    return monitor_process

def print_output(identifier, pid, channel, islogin, data):
    q = lock()
    if islogin:
        send_esc(q, f'%output {identifier} {pid} -1 {DEPTH}')
    else:
        send_esc(q, f'%output {identifier} {pid} {channel} {DEPTH}')
    send(q, data)
    send_esc(q, f'%end {identifier}')
    unlock(q)

def print_tty(message):
    q = lock()
    send_esc(q, f'%notif tty {message}')
    unlock(q)

## Infra

def fail(identifier, reason):
    log(f'fail: {reason}')
    q = begin(identifier)
    end(q, identifier, 1)

def begin(identifier):
    q = lock()
    send_esc(q, f'begin {identifier}')
    return q

def end(q, identifier, status):
    if len(PROCESSES):
        type = "f"
    else:
        type = "r"
    send_esc(q, f'end {identifier} {status} {type}')
    unlock(q)

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
        q = lock()
        send_esc(q, f'%terminate {proc.pid} {proc.return_code}')
        unlock(q)

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
            args = list(map(lambda s: base64.b64decode(s).decode('utf-8'), args))
            quit = await handle(args)
            log("flush stdout")
            sys.stdout.flush()
            if quit:
                log("Mainloop returns 0")
                return 0
            args = []

def ping():
    if len(PROCESSES):
        q = lock()
        send_esc(q, "%ping")
        unlock(q)
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
    "eval": handle_eval
}

def main():
    if sys.stdin.isatty():
        signal.signal(signal.SIGWINCH, on_sigwinch)
    try:
        asyncio.run(mainloop())
    except Exception as e:
        log(f'Exception {traceback.format_exc()}')

if __name__ == "__main__":
    main()
