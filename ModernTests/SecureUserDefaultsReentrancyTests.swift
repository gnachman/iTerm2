//
//  SecureUserDefaultsReentrancyTests.swift
//  ModernTests
//
//  “Import All Settings and Data” calls SecureUserDefaults.deserializeAll(dict:). Writing
//  a changed secure setting posts iTermSecureUserDefaults.didChange synchronously, and observers
//  such as AIModelCatalogUpdater read SecureUserDefaults.instance. If deserializeAll holds an
//  access to `instance` across that notification, the observer's access overlaps it and Swift's
//  exclusivity checker traps with “Simultaneous accesses”.
//
//  The privileged write runs an AppleScript with administrator privileges, so these tests replace
//  it with SecureUserDefaultTestHooks.privilegedWriteRunner, which writes nothing. No secure
//  setting on disk changes.
//

import XCTest
@testable import iTerm2SharedARC

final class SecureUserDefaultsReentrancyTests: XCTestCase {
    private var observer: NSObjectProtocol?

    override func setUp() {
        super.setUp()
        SecureUserDefaultTestHooks.privilegedWriteRunner = { _ in nil }
    }

    override func tearDown() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        SecureUserDefaultTestHooks.privilegedWriteRunner = nil
        // Nothing was written, so dropping the caches restores the real values.
        SecureUserDefaults.instance.allowPaste.invalidateCache()
        SecureUserDefaults.instance.enableAI.invalidateCache()
        super.tearDown()
    }

    // The serialized form of the opposite of the current value, so deserializing it is a change.
    private func flippedAllowPaste() -> [String: String] {
        let current = SecureUserDefaults.instance.allowPaste.value
        return ["AllowPaste": current ? "false" : "true"]
    }

    func testObserverCanReadInstanceDuringDeserializeAll() {
        var observedKeys = [String]()
        observer = NotificationCenter.default.addObserver(forName: iTermSecureUserDefaults.didChange,
                                                          object: nil,
                                                          queue: nil) { notification in
            // What AIModelCatalogUpdater.secureUserDefaultDidChange(_:) does.
            _ = SecureUserDefaults.instance.enableAI.key
            observedKeys.append(notification.object as? String ?? "")
        }

        SecureUserDefaults.deserializeAll(dict: flippedAllowPaste())

        XCTAssertEqual(observedKeys, ["AllowPaste"])
    }

    // The same, for the read-only Objective-C accessors observers like the composer use.
    func testObserverCanReadObjCAccessorsDuringDeserializeAll() {
        var observed = false
        observer = NotificationCenter.default.addObserver(forName: iTermSecureUserDefaults.didChange,
                                                          object: nil,
                                                          queue: nil) { _ in
            _ = iTermSecureUserDefaults.instance.aiCompletionsEnabled
            observed = true
        }

        SecureUserDefaults.deserializeAll(dict: flippedAllowPaste())

        XCTAssertTrue(observed)
    }

    func testSerializeAllIncludesEverySetting() {
        let serialized = SecureUserDefaults.serializeAll()
        for key in ["AllowPaste", "EnableAI", "AICompletions", "BrowserBundleID"] {
            XCTAssertNotNil(serialized[key], key)
        }
    }
}
