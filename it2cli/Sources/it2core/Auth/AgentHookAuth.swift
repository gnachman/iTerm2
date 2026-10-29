import Foundation
import CoreServices

/// How `it2 handle-agent-hook` gets an API cookie when the environment has none.
///
/// Other commands run osascript, which sends iTerm2 a "request cookie" AppleEvent. When macOS needs
/// the user's consent before that event may be delivered, iTerm2's AppleEvent machinery blocks a
/// serial queue on tccd until the prompt is answered, and every later AppleEvent strands a thread
/// behind it. Agent hooks fire on every tool call in every session, so an unanswered prompt
/// overnight exhausts the dispatch thread pool and hangs iTerm2 (issue 13175).
///
/// So hooks ask macOS first, without prompting, whether the event would be allowed. If consent is
/// needed and nobody is asking for it yet, a detached helper (`it2 request-consent`) asks and this
/// process waits for the answer; the helper outlives the hook if the agent kills it, so there is
/// still only one prompt. If someone is already asking, this process gives up at once rather than
/// adding to the pile.
enum AgentHookAuth {
    enum Permission: Equatable {
        case permitted
        case needsConsent
        case denied
        case notRunning
        /// tccd did not answer in time, or something else went wrong.
        case unavailable
    }

    /// The steps `credentials(_:)` is made of, injectable so the decision can be tested without
    /// TCC, a lock file, or a running iTerm2.
    struct Steps {
        /// Ask macOS whether the event would be allowed, without prompting.
        var check: () -> Permission
        /// Whether another process is already asking the user.
        var consentRequestInProgress: () -> Bool
        /// Start the consent helper and wait for it to finish.
        var runConsentHelper: () -> Void
        var requestCookie: () -> (cookie: String?, key: String?)
    }

    static func credentials(_ steps: Steps) -> (cookie: String?, key: String?) {
        // Before the check, because while a consent prompt is up tccd holds the check until the
        // prompt is answered, which would cost every hook the full check timeout.
        if steps.consentRequestInProgress() {
            return (nil, nil)
        }
        switch steps.check() {
        case .permitted:
            return steps.requestCookie()
        case .denied, .notRunning, .unavailable:
            // .unavailable includes a check that timed out because someone else's prompt is up.
            return (nil, nil)
        case .needsConsent:
            steps.runConsentHelper()
            guard steps.check() == .permitted else {
                return (nil, nil)
            }
            return steps.requestCookie()
        }
    }

    static func getCredentials() -> (cookie: String?, key: String?) {
        guard let target = Target.current() else {
            return (nil, nil)
        }
        return credentials(Steps(check: { checkPermission(target, askUser: false, timeout: checkTimeout) },
                                 consentRequestInProgress: { ConsentLock.isHeld() },
                                 runConsentHelper: { runConsentHelper(target) },
                                 requestCookie: { requestCookie(target) }))
    }

    /// The body of `it2 request-consent`. Holds the lock for as long as the prompt is up; the
    /// kernel releases it when this process exits, however that happens.
    static func requestConsent(_ target: Target) {
        guard let lock = ConsentLock.acquire() else {
            return
        }
        defer {
            close(lock)
        }
        // Another helper may have held the lock and had its prompt answered while this one
        // waited for it.
        guard checkPermission(target, askUser: false, timeout: checkTimeout) == .needsConsent else {
            return
        }
        _ = checkPermission(target, askUser: true, timeout: nil)
    }

    // MARK: - Target

    /// Which running iTerm2 to ask, chosen the same way CookieAuth.appTarget chooses one.
    enum Target: Equatable {
        case bundleID(String)
        case pid(pid_t)

        static let defaultBundleID = "com.googlecode.iterm2"

        /// nil when the instance named by an app path is not running.
        static func current() -> Target? {
            let appPath = [SocketConnection.chosenAdvertisedRecord?["app"],
                           ProcessInfo.processInfo.environment["IT2_APP_PATH"]]
                .compactMap { $0 }
                .first { !$0.isEmpty }
            guard let appPath else {
                return .bundleID(defaultBundleID)
            }
            return pid(ofAppAt: appPath).map { .pid($0) }
        }

        /// Arguments that make `it2 request-consent` address the same instance.
        var arguments: [String] {
            switch self {
            case .bundleID(let bundleID):
                return ["--bundle-id", bundleID]
            case .pid(let pid):
                return ["--pid", String(pid)]
            }
        }

        func makeDescriptor() -> AEAddressDesc {
            var desc = AEAddressDesc()
            switch self {
            case .bundleID(let bundleID):
                let bytes = Array(bundleID.utf8)
                AECreateDesc(typeApplicationBundleID, bytes, bytes.count, &desc)
            case .pid(var pid):
                AECreateDesc(typeKernelProcessID, &pid, MemoryLayout<pid_t>.size, &desc)
            }
            return desc
        }

        private static func pid(ofAppAt appPath: String) -> pid_t? {
            // realpath, not URL.resolvingSymlinksInPath, which strips a leading /private.
            // proc_pidpath keeps it, and a translocated app runs from /private/var/folders.
            guard let executable = canonicalPath((appPath as NSString)
                .appendingPathComponent("Contents/MacOS/iTerm2")) else {
                return nil
            }
            let capacity = proc_listallpids(nil, 0) + 32
            guard capacity > 32 else {
                return nil
            }
            var pids = [pid_t](repeating: 0, count: Int(capacity))
            let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
            var buffer = [CChar](repeating: 0, count: 4096)
            for pid in pids.prefix(Int(max(count, 0))) where pid > 0 {
                if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0,
                   canonicalPath(String(cString: buffer)) == executable {
                    return pid
                }
            }
            return nil
        }

        static func canonicalPath(_ path: String) -> String? {
            var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
            guard realpath(path, &buffer) != nil else {
                return nil
            }
            return String(cString: buffer)
        }
    }

    // MARK: - AppleEvents

    // The "request cookie" event, from iTerm2.sdef.
    private static let eventClass = fourCharCode("Itrm")
    private static let eventID = fourCharCode("rqck")
    private static let appNameKeyword = fourCharCode("Rcsn")

    private static let checkTimeout: TimeInterval = 2
    private static let replyTimeoutTicks = 30 * 60

    private static let errAEEventWouldRequireUserConsent: OSStatus = -1744
    private static let errAEEventNotPermitted: OSStatus = -1743

    private static func fourCharCode(_ string: String) -> OSType {
        return string.utf8.reduce(0) { ($0 << 8) | OSType($1) }
    }

    /// AEDeterminePermissionToAutomateTarget, on its own thread so that a tccd that never answers
    /// costs `timeout` seconds rather than the hook. With a nil timeout it waits indefinitely, which
    /// is what the helper wants while a prompt is up.
    private static func checkPermission(_ target: Target, askUser: Bool, timeout: TimeInterval?) -> Permission {
        final class Result: @unchecked Sendable {
            var status: OSStatus = 0
        }
        let result = Result()
        let done = DispatchSemaphore(value: 0)
        Thread {
            var desc = target.makeDescriptor()
            result.status = AEDeterminePermissionToAutomateTarget(&desc, eventClass, eventID, askUser)
            AEDisposeDesc(&desc)
            done.signal()
        }.start()
        if let timeout {
            if done.wait(timeout: .now() + timeout) == .timedOut {
                return .unavailable
            }
        } else {
            done.wait()
        }
        switch result.status {
        case noErr:
            return .permitted
        case errAEEventWouldRequireUserConsent:
            return .needsConsent
        case errAEEventNotPermitted:
            return .denied
        case OSStatus(procNotFound):
            return .notRunning
        default:
            return .unavailable
        }
    }

    private static func requestCookie(_ target: Target) -> (cookie: String?, key: String?) {
        var address = target.makeDescriptor()
        defer {
            AEDisposeDesc(&address)
        }
        var event = AppleEvent()
        guard AECreateAppleEvent(eventClass, eventID, &address,
                                 AEReturnID(kAutoGenerateReturnID), AETransactionID(kAnyTransactionID),
                                 &event) == noErr else {
            return (nil, nil)
        }
        defer {
            AEDisposeDesc(&event)
        }
        let appName = Array("it2".utf8)
        guard AEPutParamPtr(&event, appNameKeyword, typeUTF8Text, appName, appName.count) == noErr else {
            return (nil, nil)
        }

        var reply = AppleEvent()
        defer {
            AEDisposeDesc(&reply)
        }
        guard AESendMessage(&event, &reply, AESendMode(kAEWaitReply | kAENeverInteract),
                            replyTimeoutTicks) == noErr else {
            return (nil, nil)
        }

        var errorNumber: Int32 = 0
        var actualType: DescType = 0
        var actualSize = 0
        if AEGetParamPtr(&reply, keyErrorNumber, typeSInt32, &actualType, &errorNumber,
                         MemoryLayout<Int32>.size, &actualSize) == noErr, errorNumber != 0 {
            return (nil, nil)
        }

        var result = AEDesc()
        guard AEGetParamDesc(&reply, keyDirectObject, typeUTF8Text, &result) == noErr else {
            return (nil, nil)
        }
        defer {
            AEDisposeDesc(&result)
        }
        var bytes = [UInt8](repeating: 0, count: AEGetDescDataSize(&result))
        AEGetDescData(&result, &bytes, bytes.count)

        // "COOKIE KEY", as osascript would print it.
        let parts = String(decoding: bytes, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else {
            return (nil, nil)
        }
        return (String(parts[0]), String(parts[1]))
    }

    // MARK: - Helper process

    /// Runs `it2 request-consent` in its own session with no inherited file descriptors, and waits
    /// for it. Its own session so that the agent killing the hook does not take the prompt down
    /// with it; no inherited descriptors because the agent reads the hook's output until it closes,
    /// and a helper holding that pipe open would hold up the agent just as surely as prompting
    /// inline would.
    private static func runConsentHelper(_ target: Target) {
        guard let executable = Bundle.main.executablePath else {
            return
        }
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer {
            posix_spawn_file_actions_destroy(&fileActions)
        }
        posix_spawn_file_actions_addopen(&fileActions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, 2, "/dev/null", O_WRONLY, 0)

        let arguments = [executable, "request-consent"] + target.arguments
        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer {
            argv.forEach { free($0) }
        }

        var pid: pid_t = 0
        guard posix_spawn(&pid, executable, &fileActions, &attributes, &argv, environ) == 0 else {
            return
        }
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {
        }
    }
}

/// An advisory lock held by the consent helper for as long as its prompt is up. The kernel releases
/// it when the helper exits, so a crashed or killed helper never leaves it held.
///
/// The helper takes it exclusively and hooks probe it with a shared lock. So probes never collide
/// with each other, which would make a hook give up for no reason, and a probe can only delay the
/// helper for a moment rather than turn it away.
///
/// One lock for every iTerm2 build: macOS asks for consent per target bundle identifier, which all
/// builds share, so a prompt pending for one is a prompt pending for all of them.
enum ConsentLock {
    static var defaultPath: String {
        let appSupport = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory,
                                                             .userDomainMask,
                                                             true).first!
        return "\(appSupport)/iTerm2/it2-consent.lock"
    }

    /// Take the lock exclusively, waiting for another helper to finish with it. nil if the file
    /// can't be opened.
    static func acquire(path: String = defaultPath) -> Int32? {
        guard let fd = openLockFile(path) else {
            return nil
        }
        while flock(fd, LOCK_EX) != 0 {
            guard errno == EINTR else {
                close(fd)
                return nil
            }
        }
        return fd
    }

    /// Whether a helper is asking right now. A lock file that can't be opened counts as held: the
    /// helper couldn't take it either, so starting one would only fail.
    static func isHeld(path: String = defaultPath) -> Bool {
        guard let fd = openLockFile(path) else {
            return true
        }
        defer {
            close(fd)
        }
        return flock(fd, LOCK_SH | LOCK_NB) != 0
    }

    private static func openLockFile(_ path: String) -> Int32? {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        // O_NOFOLLOW so a symlink planted at the lock path can't make us create a file elsewhere.
        let fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        return fd >= 0 ? fd : nil
    }
}
