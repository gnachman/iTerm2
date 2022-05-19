#!/usr/bin/env python3
import asyncio
import base64
import fcntl
import os
import pty
import pwd
import random
import signal
import subprocess
import sys
import termios
import traceback

# pid -> Process
PROCESSES = {}
# List of pids that are completed. Their tasks can be awaited and removed.
COMPLETED = []
VERBOSE=1
LOGFILE=None

def log(message):
    if VERBOSE:
        global LOGFILE
        if not LOGFILE:
            LOGFILE = open("/tmp/framer.txt", "w")
        print(f'DEBUG {os.getpid()}: {message}', file=LOGFILE)
        LOGFILE.flush()

def send(text):
    log("> " + str(text))
    print(text)

class Process:
    @staticmethod
    async def run_tty(executable, args, cwd, env):
        master, slave = pty.openpty()
        try:
            def set_ctty(ctty_fd, master_fd):
                os.setsid()
                os.close(master_fd)
                fcntl.ioctl(ctty_fd, termios.TIOCSCTTY, 0)
            log(env)
            proc = await asyncio.create_subprocess_exec(
                *args,
                stdin=slave,
                stdout=slave,
                stderr=slave,
                cwd=cwd,
                env=env,
                executable=executable,
                preexec_fn=lambda: set_ctty(slave, master))
        except Exception as e:
            log(e)
        finally:
            os.close(slave)
        return await Process.run_tty_proc(proc, master)

    @staticmethod
    async def run_shell_tty(command):
        master, slave = pty.openpty()
        try:
            proc = await asyncio.create_subprocess_shell(
                command,
                stdin=slave,
                stdout=slave,
                stderr=slave)
        finally:
            os.close(slave)
        return await Process.run_tty_proc(proc, master)

    @staticmethod
    async def run_tty_proc(proc, master):
        pipe = open(master, 'wb', 0)
        writer = await Process._writer(pipe)
        reader, _ = await Process._reader(pipe)
        process = Process(proc, writer, reader, None, master=master)
        # No need to close reader's transport because it's the same file descriptor as master.
        return process

    @staticmethod
    async def run_shell(command):
        read1, write1 = os.pipe()
        read2, write2 = os.pipe()
        read3, write3 = os.pipe()
        proc = await asyncio.create_subprocess_shell(command, stdin=read1, stderr=write2, stdout=write3)
        writer = await Process.writer(write1)
        stderr_reader, stderr_tx = await Process.reader(read2)
        stdout_reader, stdout_tx = await Process.reader(read3)
        proc = Process(proc, writer, stdout_reader, stderr_reader)
        def cleanup():
            stderr_tx.close()
            stdout_tx.close()
        proc.add_cleanup(cleanup)
        return proc

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

    def __init__(self, process, writer, stdout_reader, stderr_reader, master=None):
        self.__process = process
        self.__writer = writer
        self.__stdout_reader = stdout_reader
        self.__stderr_reader = stderr_reader
        self.__stdout_read_handler = None
        self.__stderr_read_handler = None
        self.__cleanup = []
        self.__return_code = None
        self.__master = master

    @property
    def master(self):
        return self.__master

    async def cleanup(self):
        log(f'cleanup process {self.pid}')
        if self.__return_code is None:
            log("kill")
            await self.kill(signal.SIGKILL)
            log("wait")
            await self.wait()
        log('close writer tx')
        self.__writer.transport.close()
        # StreamReader doesn't have a transport so it must be closed by a __cleanup function.
        for f in self.__cleanup:
            f()

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
                log(f'reading for channel {channel}')
                value = await reader.read(256)
                log(f'read {value} for channel {channel}')
                coro = callback(channel, value)
                if coro:
                    log(f'await callback-returned coro {coro}')
                    await coro
                if len(value) == 0:
                    return
        except Exception as e:
            log(e)

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

## Commands

async def handle_login(identifier, args):
    log("begin handle_login")
    cwd = args[0]
    args = args[1:]
    cwd = os.path.expandvars(os.path.expanduser(cwd))
    login_shell = guess_login_shell()
    log(f'Login shell is {login_shell}')
    try:
        _, shell_name = os.path.split(login_shell)
        proc = await Process.run_tty(
            login_shell,
            ["-" + shell_name] + args,
            cwd,
            os.environ)
    except Exception as e:
        log(e)
    log("login shell started")
    global PROCESSES
    PROCESSES[proc.pid] = proc
    begin(identifier)
    send(proc.pid)
    end(identifier, 0)
    await proc.handle_read(make_monitor_process(identifier, proc))
    return False

async def handle_run(identifier, args):
    """Run a command inside the user's shell"""
    try:
        proc = await Process.run_shell_tty(args[0])
    except Exception as e:
        log(e)
    global PROCESSES
    PROCESSES[proc.pid] = proc
    begin(identifier)
    print(proc.pid)
    end(identifier, 0)
    await proc.handle_read(make_monitor_process(identifier, proc))
    return False

async def handle_send(identifier, args):
    if len(args) < 2:
        fail("not enough arguments")
    try:
        pid = int(args[0])
        decoded = base64.b64decode(args[1])
    except Exception as e:
        log(f'Exception {e}')
        fail("exception decoding argument")
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
        fail("pid not an int")
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
    return True

## Helpers for run()

async def start_process(args):
    runid = random.randint(0, 10000000000000000000)
    PROCESSES[runid] = proc
    return runid

def make_monitor_process(identifier, proc):
    def monitor_process(channel, value):
        log(f'monitor_process called with channel={channel} value={value}')
        if len(value) == 0:
            global COMPLETED
            COMPLETED.append(proc.pid)
            return cleanup()
        print_output(identifier, proc.pid, channel, value)
        return None
    return monitor_process

async def communicate(identifier, proc, input_bytes):
    outdata, errdata = await proc.communicate(input_bytes)
    if outdata:
        print_output(identifier, "0", outdata)
    if errdata:
        print_output(identifier, "1", errdata)
    return outdata, errdata

def print_output(identifier, pid, channel, data):
    send(f'%output {identifier} {pid} {channel}')
    data = data
    encoded = base64.b64encode(data).decode("utf-8")
    n = 128
    for i in range(0, len(encoded), n):
        part = encoded[i:i+n]
        send(part)
    send(f'%end {identifier}')

## Infra

def fail(reason):
    log(f'fail: {reason}')
    try:
        raise ValueError
    except ValueError:
        tb = traceback.format_exc()
        log(tb)
    send(f'abort {reason}')
    sys.exit(-1)

def begin(identifier):
    send(f'begin {identifier}')

def end(identifier, status):
    send(f'end {identifier} {status}')

async def cleanup():
    """Await tasks that have completed, clear the COMPLETED list, and remove them from TASKS."""
    log("cleaning up")
    global COMPLETED
    completed = list(COMPLETED)
    COMPLETED = []
    for pid in completed:
        if pid not in PROCESSES:
            continue
        proc = PROCESSES[pid]
        del PROCESSES[pid]
        await proc.cleanup()
        send(f'%terminate {proc.pid} {proc.return_code}')

async def handle(args):
    log(f'handle {args}')
    if len(args) == 0:
        fail("no args")
        return True
    cmd = args[0]
    del args[0]
    identifier = random.randint(0, 10000000000000000000)
    if cmd not in HANDLERS:
        fail("unrecognized command")

    f = HANDLERS[cmd]
    log(f'handler is {f}')
    should_quit = False
    try:
        should_quit = await f(identifier, args)
    except Exception as e:
        log(f'Handler for {cmd} threw {e}')
    log("call cleanup()")
    await cleanup()
    return should_quit

def read_line():
    try:
        log("Calling sys.stdin.readline")
        return sys.stdin.readline().rstrip('\n')
    except:
        log("Caught exception")
        sys.exit(1)

async def mainloop():
    args = []
    while True:
        log("reading")
        try:
            line = await asyncio.get_event_loop().run_in_executor(None, read_line)
        except:
            fail("exception during read_line")
            return
        log(f'read from stdin "{line}" with length {len(line)}')
        if len(line):
            if len(args) and args[-1].endswith("\\"):
                args[-1] = args[-1][:-1] + line
            else:
                args.append(line)
            log(f'args is now {args}')
        else:
            quit = await handle(args)
            if quit:
                log("Mainloop returns 0")
                return 0
            args = []

async def update_pty_size():
    log(f'update_pty_size')
    window_size = fcntl.ioctl(sys.stdin.fileno(), termios.TIOCGWINSZ, '00000000')
    for pid in PROCESSES:
        proc = PROCESSES[pid]
        master = proc.master
        if master is not None:
            log(f'TIOCSWINSZ {proc}')
            fcntl.ioctl(master, termios.TIOCSWINSZ, window_size)
        else:
            log(f'no master fd for {proc}')

def on_sigwinch(_sig, _stack):
    log(f'Received SIGWINCH')
    loop = asyncio.get_event_loop()
    asyncio.run_coroutine_threadsafe(update_pty_size(), loop)

HANDLERS = {
    "run": handle_run,
    "login": handle_login,
    "send": handle_send,
    "kill": handle_kill,
    "quit": handle_quit}

def main():
    if sys.stdin.isatty():
        signal.signal(signal.SIGWINCH, on_sigwinch)
    asyncio.run(mainloop())

if __name__ == "__main__":
    main()
