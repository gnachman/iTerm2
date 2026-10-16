//
//  iTermTestHostIsolation.swift
//  iTerm2
//
//  Created by George Nachman on 10/16/26.
//

import Foundation

// Gives each unit-test host its own settings suite.
//
// Parallel test runs launch several test hosts with the same -suite. They used to share one
// settings domain, Application Support folder, and config folder, so a setting one test changed
// was visible to the other workers, and a worker that crashed before restoring it left it set for
// every later run. Instead, a test host launched with -suite NAME uses NAME.<pid>-<random>, seeded
// from NAME, which is never written. State left by test hosts that are no longer running is
// removed.
//
// This works on preference files directly rather than through NSUserDefaults. Removing a domain
// through the API makes cfprefsd write an empty file back when the process exits, and a suite
// name is never reused, so cfprefsd never has a stale copy of a file written here.
@objc(iTermTestHostIsolation)
class TestHostIsolation: NSObject {
    struct Paths {
        var preferencesDirectory: URL
        var applicationSupportDirectory: URL
        var configDirectory: URL
        var homeDirectory: URL
        var temporaryDirectory: URL

        // Where the app keeps per-suite state. See NSFileManager+iTerm.m and
        // iTermInstanceLock.swift.
        static var current: Paths {
            let home = URL(fileURLWithPath: NSHomeDirectory())
            return Paths(preferencesDirectory: home.appendingPathComponent("Library/Preferences"),
                         applicationSupportDirectory: home.appendingPathComponent("Library/Application Support"),
                         configDirectory: home.appendingPathComponent(".config"),
                         homeDirectory: home,
                         temporaryDirectory: URL(fileURLWithPath: NSTemporaryDirectory()))
        }
    }

    // Same test as -[NSApplication isRunningUnitTests], which can't be used before NSApp exists.
    static func isTestHost(environment: [String: String]) -> Bool {
        return environment["XCInjectBundle"] != nil || environment["XCInjectBundleInto"] != nil
    }

    // Call from main() before any user defaults access. Returns the suite to use in place of
    // `base`, which is `base` itself unless this process is a test host.
    @objc(suiteNameForBase:)
    static func suiteName(forBase base: String) -> String {
        guard isTestHost(environment: ProcessInfo.processInfo.environment) else {
            return base
        }
        return suiteName(forBase: base,
                         pid: getpid(),
                         nonce: UInt32.random(in: 0...UInt32.max),
                         paths: .current) { pid in
            kill(pid, 0) == 0 || errno == EPERM
        }
    }

    static func suiteName(forBase base: String,
                          pid: pid_t,
                          nonce: UInt32,
                          paths: Paths,
                          isAlive: (pid_t) -> Bool) -> String {
        var removed = 0
        for (suite, owner) in testHostSuites(base: base, paths: paths) where owner != pid && !isAlive(owner) {
            removeState(suite: suite, paths: paths)
            removed += 1
        }
        if removed > 0 {
            RLog("Removed state of \(removed) earlier test hosts for suite \(base)")
        }

        let suite = "\(base).\(pid)-\(nonce)"
        for domain in ["", ".private"] {
            seed(suite + domain, from: base + domain, paths: paths)
        }
        return suite
    }

    // Suites of test hosts that left any state behind, found by name, with the pid of each.
    static func testHostSuites(base: String, paths: Paths) -> [String: pid_t] {
        let fm = FileManager.default
        func names(in dir: URL) -> [String] {
            return (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        }
        // Each candidate is a name with a fixed prefix and suffix around the suite name.
        var candidates = [String]()
        for name in names(in: paths.preferencesDirectory) {
            for suffix in [".private.plist", ".plist"] where name.hasSuffix(suffix) {
                candidates.append(String(name.dropLast(suffix.count)))
                break
            }
        }
        candidates += names(in: paths.applicationSupportDirectory)
        candidates += names(in: paths.configDirectory)
        candidates += names(in: paths.homeDirectory).filter { $0.hasPrefix(".") }.map { String($0.dropFirst()) }
        let lockPrefix = "iTerm2.instance."
        let lockSuffix = ".lock"
        candidates += names(in: paths.temporaryDirectory)
            .filter { $0.hasPrefix(lockPrefix) && $0.hasSuffix(lockSuffix) }
            .map { String($0.dropFirst(lockPrefix.count).dropLast(lockSuffix.count)) }

        // A suite is base.<pid>-<nonce>, both decimal.
        let prefix = base + "."
        var result = [String: pid_t]()
        for name in candidates where name.hasPrefix(prefix) {
            let parts = name.dropFirst(prefix.count).split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
                  let pid = pid_t(parts[0]),
                  UInt32(parts[1]) != nil else {
                continue
            }
            result[name] = pid
        }
        return result
    }

    private static func removeState(suite: String, paths: Paths) {
        let fm = FileManager.default
        for url in [paths.preferencesDirectory.appendingPathComponent(suite + ".plist"),
                    paths.preferencesDirectory.appendingPathComponent(suite + ".private.plist"),
                    paths.applicationSupportDirectory.appendingPathComponent(suite),
                    paths.configDirectory.appendingPathComponent(suite),
                    paths.homeDirectory.appendingPathComponent("." + suite),
                    paths.temporaryDirectory.appendingPathComponent("iTerm2.instance.\(suite).lock")] {
            try? fm.removeItem(at: url)
        }
    }

    // Copies the source domain's file, if there is one. A missing or unreadable source leaves the
    // new domain empty.
    private static func seed(_ domain: String, from source: String, paths: Paths) {
        let sourceURL = paths.preferencesDirectory.appendingPathComponent(source + ".plist")
        guard let data = try? Data(contentsOf: sourceURL),
              (try? PropertyListSerialization.propertyList(from: data, format: nil)) is [String: Any] else {
            return
        }
        try? data.write(to: paths.preferencesDirectory.appendingPathComponent(domain + ".plist"))
    }
}
