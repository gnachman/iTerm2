//
//  LiveShell.swift
//  iTerm2 shell-integration live harness support
//
//  Spawns a real shell via `forkpty(3)` so it has a proper controlling tty
//  (interactive shells like fish refuse to run otherwise), and forwards
//  every byte the shell writes to a caller-supplied callback. No parsing
//  here — the harness pipes those bytes into a real VT100Screen and asserts
//  on its VT100ScreenMark state.
//
//  Only used by ShellIntegrationLiveHarness. Not part of the default unit
//  test sweep.
//

import Foundation
import Darwin

final class LiveShell {
    enum LiveShellError: Error, CustomStringConvertible {
        case forkptyFailed(errno: Int32)
        case shellNotFound(path: String)
        case timedOut(waitingFor: String)

        var description: String {
            switch self {
            case .forkptyFailed(let e): return "forkpty failed: errno \(e)"
            case .shellNotFound(let p): return "shell not found at \(p)"
            case .timedOut(let w):      return "timed out waiting for \(w)"
            }
        }
    }

    private let masterFD: Int32
    private let childPID: pid_t
    private let stateLock = NSLock()
    private var _exited = false

    /// Whether the child process has exited.
    var hasExited: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return _exited
    }

    /// Launch `shellPath` with the supplied argv (argv[0] included) and env.
    /// Each chunk the shell writes is delivered to `onBytes` synchronously
    /// from the reader thread.
    init(shellPath: String,
         arguments: [String],
         environment: [String: String],
         onBytes: @escaping (UnsafePointer<CChar>, Int) -> Void) throws {
        guard FileManager.default.fileExists(atPath: shellPath) else {
            throw LiveShellError.shellNotFound(path: shellPath)
        }

        var masterFD: Int32 = -1
        var term = termios.shellIntegrationDefault
        var size = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        // Build the C argv and envp arrays before forking. After forkpty
        // returns 0 in the child, we cannot safely call into Swift; only
        // POSIX C primitives are safe.
        let cArgv = Self.makeCStringArray(arguments)
        var envArray: [String] = []
        for (k, v) in environment { envArray.append("\(k)=\(v)") }
        let cEnvp = Self.makeCStringArray(envArray)

        let pid = forkpty(&masterFD, nil, &term, &size)
        if pid < 0 {
            Self.freeCStringArray(cArgv)
            Self.freeCStringArray(cEnvp)
            throw LiveShellError.forkptyFailed(errno: errno)
        }
        if pid == 0 {
            // Child. forkpty already gave us a controlling tty and made
            // stdin/stdout/stderr point at the pty slave.
            _ = execve(shellPath, cArgv, cEnvp)
            _exit(127)
        }
        // Parent.
        self.masterFD = masterFD
        self.childPID = pid
        Self.freeCStringArray(cArgv)
        Self.freeCStringArray(cEnvp)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.readLoop(onBytes: onBytes)
        }
    }

    deinit {
        if !hasExited {
            kill(childPID, SIGKILL)
            _ = waitpid(childPID, nil, 0)
        }
        close(masterFD)
    }

    /// Write `text` to the shell's stdin.
    @discardableResult
    func send(_ text: String) -> Int {
        guard let bytes = text.data(using: .utf8) else { return 0 }
        var sent = 0
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            while sent < bytes.count {
                let n = Darwin.write(masterFD, base.advanced(by: sent), bytes.count - sent)
                if n < 0 { if errno == EINTR { continue } else { break } }
                if n == 0 { break }
                sent += n
            }
        }
        return sent
    }

    /// Poll-wait until `predicate` returns true or `timeout` elapses.
    func waitUntil(_ description: String,
                   timeout: TimeInterval,
                   pollInterval: TimeInterval = 0.02,
                   _ predicate: () -> Bool) throws {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if predicate() { return }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        throw LiveShellError.timedOut(waitingFor: description)
    }

    /// Send `exit\n` and wait for the child to terminate, then SIGKILL if it
    /// hangs around.
    func terminate(within timeout: TimeInterval = 2.0) {
        send("exit\n")
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if hasExited { return }
            Thread.sleep(forTimeInterval: 0.02)
        }
        if !hasExited {
            kill(childPID, SIGKILL)
        }
    }

    // MARK: - Private

    private func readLoop(onBytes: (UnsafePointer<CChar>, Int) -> Void) {
        var buffer = [CChar](repeating: 0, count: 4096)
        while true {
            let n = buffer.withUnsafeMutableBufferPointer { ptr -> Int in
                return read(masterFD, ptr.baseAddress, ptr.count)
            }
            if n > 0 {
                buffer.withUnsafeBufferPointer { ptr in
                    onBytes(ptr.baseAddress!, n)
                }
                continue
            }
            if n == 0 || errno != EINTR {
                stateLock.lock()
                _exited = true
                stateLock.unlock()
                _ = waitpid(childPID, nil, WNOHANG)
                return
            }
        }
    }

    private static func makeCStringArray(_ strings: [String]) -> UnsafeMutablePointer<UnsafeMutablePointer<CChar>?> {
        let ptr = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: strings.count + 1)
        for (i, s) in strings.enumerated() {
            ptr[i] = strdup(s)
        }
        ptr[strings.count] = nil
        return ptr
    }

    private static func freeCStringArray(_ array: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) {
        var i = 0
        while let s = array[i] {
            free(s)
            i += 1
        }
        array.deallocate()
    }
}

private extension termios {
    /// A termios for interactive shell use under our PTY harness. ECHO
    /// kept ON because some shells (fish) depend on the tty reflecting
    /// their typed bytes for line editing to work correctly.
    static var shellIntegrationDefault: termios = {
        let ctrl = { (c: String) -> cc_t in cc_t(c.utf8[c.utf8.startIndex] - 64) }
        return termios(
            c_iflag: tcflag_t(ICRNL | IXON | IXANY | IMAXBEL | BRKINT | IUTF8),
            c_oflag: tcflag_t(OPOST | ONLCR),
            c_cflag: tcflag_t(CREAD | CS8 | HUPCL),
            c_lflag: tcflag_t(ICANON | ISIG | IEXTEN | ECHO | ECHOE | ECHOK | ECHOKE | ECHOCTL),
            c_cc: (ctrl("D"), cc_t(0xff), cc_t(0xff), cc_t(0x7f),
                   ctrl("W"), ctrl("U"), ctrl("R"), cc_t(0),
                   ctrl("C"), cc_t(0x1c), ctrl("Z"), ctrl("Y"),
                   ctrl("Q"), ctrl("S"), ctrl("V"), ctrl("O"),
                   cc_t(1), cc_t(0), cc_t(0), ctrl("T")),
            c_ispeed: speed_t(B38400),
            c_ospeed: speed_t(B38400))
    }()
}
