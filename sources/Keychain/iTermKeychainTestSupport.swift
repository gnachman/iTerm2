//
//  iTermKeychainTestSupport.swift
//  iTerm2
//
//  Test-only launch hook to reset the data-protection keychain between migration
//  tests. Because those items are entitlement-gated, only the signed `make run-keychain`
//  build can read or delete them, and the plain `security` CLI cannot. This lets that
//  build purge the app's own data-protection items (scoped to our access group, so it
//  can never touch another app's) when launched with a specific flag, then quit.
//
//  This whole class is wrapped in `#if ITERM_DEBUG` (defined only in the Development
//  configuration via OTHER_SWIFT_FLAGS), so it PHYSICALLY does not exist in a
//  Beta/Nightly/Deployment binary, not merely uncalled. Its single call site in
//  iTermApplicationDelegate is likewise `#ifdef ITERM_DEBUG`. It also only acts when the
//  specific launch flag is present. See `make purge-keychain-test`.
//

import Foundation

#if ITERM_DEBUG
@objc(iTermKeychainTestSupport)
final class iTermKeychainTestSupport: NSObject {
    private static let purgeFlag = "--iterm2-purge-data-protection-keychain-for-testing"
    private static let resultPath = "/tmp/iterm2-keychain-purge-result.txt"

    /// If the purge launch flag is present, delete the app's data-protection keychain
    /// items, write a one-line result to a temp file for the caller, and exit before the
    /// rest of launch (so no keychain read races the purge).
    @objc static func handlePurgeLaunchFlagIfPresent() {
        guard CommandLine.arguments.contains(purgeFlag) else { return }
        let count = iTermUpgradeSafeKeychain.purgeAllDataProtectionItemsForTesting()
        let message = "purged data-protection keychain: matched \(count.map(String.init) ?? "n/a (no access group)") item(s)\n"
        try? message.write(toFile: resultPath, atomically: true, encoding: .utf8)
        exit(0)
    }
}
#endif
