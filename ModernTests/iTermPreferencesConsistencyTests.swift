import Foundation
import ObjectiveC.runtime
import XCTest
@testable import iTerm2SharedARC

private final class CoordinatedUserDefaults: UserDefaults {
    private var storage = [String: Any]()
    private var blockedKey: String?
    private var snapshotTakenSemaphore = DispatchSemaphore(value: 0)
    private var resumeBlockedReadSemaphore = DispatchSemaphore(value: 0)

    init() {
        super.init(suiteName: UUID().uuidString)!
    }

    override func object(forKey defaultName: String) -> Any? {
        if blockedKey == defaultName {
            let snapshot = storage[defaultName]
            blockedKey = nil
            snapshotTakenSemaphore.signal()
            resumeBlockedReadSemaphore.wait()
            return snapshot
        }
        return storage[defaultName]
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        if let value {
            storage[defaultName] = value
        } else {
            storage.removeValue(forKey: defaultName)
        }
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: self)
    }

    override func removeObject(forKey defaultName: String) {
        storage.removeValue(forKey: defaultName)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: self)
    }

    func setRawObject(_ object: Any?, forKey key: String) {
        if let object {
            storage[key] = object
        } else {
            storage.removeValue(forKey: key)
        }
    }

    func storedObject(forKey key: String) -> Any? {
        storage[key]
    }

    func blockNextRead(forKey key: String) {
        blockedKey = key
        snapshotTakenSemaphore = DispatchSemaphore(value: 0)
        resumeBlockedReadSemaphore = DispatchSemaphore(value: 0)
    }

    func waitForBlockedRead(timeout: TimeInterval) -> Bool {
        snapshotTakenSemaphore.wait(timeout: .now() + timeout) == .success
    }

    func resumeBlockedRead() {
        resumeBlockedReadSemaphore.signal()
    }
}

final class iTermPreferencesConsistencyTests: XCTestCase {
    private func setUserDefaultsOverrideForTesting(_ defaults: UserDefaults?) {
        let selector = NSSelectorFromString("setUserDefaultsOverrideForTesting:")
        guard let method = class_getClassMethod(iTermPreferences.self, selector) else {
            XCTFail("Missing testing hook \(selector)")
            return
        }
        typealias Function = @convention(c) (AnyClass, Selector, UserDefaults?) -> Void
        let implementation = method_getImplementation(method)
        unsafeBitCast(implementation, to: Function.self)(iTermPreferences.self, selector, defaults)
    }

    private func resetPreferenceCacheForTesting() {
        let selector = NSSelectorFromString("resetPreferenceCacheForTesting")
        guard let method = class_getClassMethod(iTermPreferences.self, selector) else {
            XCTFail("Missing testing hook \(selector)")
            return
        }
        typealias Function = @convention(c) (AnyClass, Selector) -> Void
        let implementation = method_getImplementation(method)
        unsafeBitCast(implementation, to: Function.self)(iTermPreferences.self, selector)
    }

    private func writeInteger(_ value: Int, toSuite suiteName: String, key: String) throws {
        let process = Process()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", suiteName, key, "-int", String(value)]
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = standardError.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? ""
            XCTFail("defaults write failed for suite \(suiteName): \(message)")
        }
    }

    override func tearDown() {
        setUserDefaultsOverrideForTesting(nil)
        resetPreferenceCacheForTesting()
        super.tearDown()
    }

    func testColdReadDoesNotOverwriteNewerWrite() {
        let defaults = CoordinatedUserDefaults()
        setUserDefaultsOverrideForTesting(defaults)
        resetPreferenceCacheForTesting()
        defaults.setRawObject(5, forKey: kPreferenceKeyTopBottomMargins)
        defaults.blockNextRead(forKey: kPreferenceKeyTopBottomMargins)

        let group = DispatchGroup()
        var staleRead = Int.min
        group.enter()
        DispatchQueue.global().async {
            staleRead = Int(iTermPreferences.int(forKey: kPreferenceKeyTopBottomMargins))
            group.leave()
        }

        XCTAssertTrue(defaults.waitForBlockedRead(timeout: 1),
                      "Timed out waiting for the cold read to capture its snapshot")

        iTermPreferences.setInt(10, forKey: kPreferenceKeyTopBottomMargins)
        XCTAssertEqual((defaults.storedObject(forKey: kPreferenceKeyTopBottomMargins) as? NSNumber)?.intValue,
                       10)

        defaults.resumeBlockedRead()
        XCTAssertEqual(group.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(staleRead, 5)
        XCTAssertEqual(Int(iTermPreferences.int(forKey: kPreferenceKeyTopBottomMargins)),
                       10,
                       "A stale cold read must not overwrite a newer in-process write")
    }

    func testExternalProcessWriteInvalidatesCache() throws {
        let suiteName = "com.iterm2.prefcache.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        setUserDefaultsOverrideForTesting(defaults)
        resetPreferenceCacheForTesting()

        defaults.set(5, forKey: kPreferenceKeyTopBottomMargins)
        XCTAssertEqual(Int(iTermPreferences.int(forKey: kPreferenceKeyTopBottomMargins)), 5)

        try writeInteger(8, toSuite: suiteName, key: kPreferenceKeyTopBottomMargins)
        XCTAssertEqual((defaults.object(forKey: kPreferenceKeyTopBottomMargins) as? NSNumber)?.intValue,
                       8)
        XCTAssertEqual(Int(iTermPreferences.int(forKey: kPreferenceKeyTopBottomMargins)),
                       8,
                       "Cache should refresh after the backing defaults domain changes out of process")
    }
}
