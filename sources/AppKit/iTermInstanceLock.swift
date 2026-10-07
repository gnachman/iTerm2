//
//  iTermInstanceLock.swift
//  iTerm2
//
//  Created by George Nachman on 10/6/26.
//

import AppKit

// Prevents two instances from sharing a user defaults domain (the -suite, or the bundle's own
// domain when there is no suite). They would clobber each other's settings and saved state.
@objc(iTermInstanceLock)
class InstanceLock: NSObject {
    private static var conflictingPID: pid_t?

    // Call as early as possible in main(), after the custom suite name is set. Takes an exclusive
    // lock that lasts for the life of the process.
    @objc static func acquire() {
        let domain = iTermUserDefaults.customSuiteName() ?? Bundle.main.bundleIdentifier ?? "iTerm2"
        let safeDomain = domain.replacingOccurrences(of: "/", with: "_")
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("iTerm2.instance.\(safeDomain).lock")
        // O_CLOEXEC keeps child processes (e.g., the multiserver) from holding the lock after we exit.
        let fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        if fd < 0 {
            // Don't refuse to launch just because the lock file is unavailable.
            RLog("Could not open \(path): \(String(cString: strerror(errno)))")
            return
        }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            // Leak fd intentionally. The lock is released when the process exits.
            let pidString = "\(getpid())\n"
            if ftruncate(fd, 0) == 0 {
                _ = pidString.withCString { pwrite(fd, $0, strlen($0), 0) }
            }
            return
        }
        let savedErrno = errno
        var buffer = [CChar](repeating: 0, count: 32)
        _ = pread(fd, &buffer, buffer.count - 1, 0)
        close(fd)
        if savedErrno != EWOULDBLOCK {
            RLog("Could not lock \(path): \(String(cString: strerror(savedErrno)))")
            return
        }
        let pid = pid_t(atoi(buffer))
        RLog("Instance lock \(path) is held by pid \(pid)")
        conflictingPID = pid
    }

    // Call once NSApp exists. If another instance holds the lock, ask the user what to do. Quitting
    // activates the other instance and exits.
    @objc static func resolveConflictIfNeeded() {
        guard let pid = conflictingPID else {
            return
        }
        let message: String
        if let suiteName = iTermUserDefaults.customSuiteName() {
            message = String(format: String(localized: "InstanceLock.SuiteMessage",
                                            defaultValue: "Another copy of iTerm2 (process ID %1$d) is already running with the settings suite “%2$@”. If two copies use the same settings at once, they can overwrite each other’s preferences and saved windows.",
                                            comment: "Shown at launch when another instance uses the same -suite. %1$d is a process ID; %2$@ is the suite name."),
                             Int32(pid), suiteName)
        } else {
            message = String(format: String(localized: "InstanceLock.Message",
                                            defaultValue: "Another copy of iTerm2 (process ID %d) is already running. If two copies use the same settings at once, they can overwrite each other’s preferences and saved windows.",
                                            comment: "Shown at launch when another instance of iTerm2 is already running. %d is a process ID."),
                             Int32(pid))
        }
        let quit = String(localized: "InstanceLock.Quit",
                          defaultValue: "Quit",
                          comment: "Button that quits this copy of iTerm2 and switches to the one already running")
        let launchAnyway = String(localized: "InstanceLock.LaunchAnyway",
                                  defaultValue: "Launch Anyway",
                                  comment: "Button that keeps launching a second copy of iTerm2 despite the risk")
        let selection = iTermWarning.show(withTitle: message,
                                          actions: [quit, launchAnyway],
                                          accessory: nil,
                                          identifier: nil,
                                          silenceable: .kiTermWarningTypePersistent,
                                          heading: String(localized: "InstanceLock.Heading",
                                                          defaultValue: "iTerm2 Is Already Running",
                                                          comment: "Heading of the warning shown when launching a second copy of iTerm2"),
                                          window: nil)
        if selection == .kiTermWarningSelection1 {
            RLog("User chose to launch anyway despite pid \(pid) holding the instance lock")
            return
        }
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
        exit(0)
    }
}
