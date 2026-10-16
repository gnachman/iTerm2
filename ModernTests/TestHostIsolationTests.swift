//
//  TestHostIsolationTests.swift
//  iTerm2
//
//  Created by George Nachman on 10/16/26.
//

import XCTest
@testable import iTerm2SharedARC

// Parallel test hosts used to share one settings domain and one Application
// Support folder, so a setting a test changed was visible to other workers and,
// when a worker crashed before restoring it, to every later run.
final class TestHostIsolationTests: XCTestCase {
    private let base = "iterm2-tests"
    private var root: URL!
    private var paths: TestHostIsolation.Paths!

    override func setUpWithError() throws {
        // Everything lives in a temporary directory, including the preferences
        // folder, so these tests never touch real settings.
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestHostIsolationTests-\(UUID().uuidString)")
        paths = TestHostIsolation.Paths(preferencesDirectory: root.appendingPathComponent("Preferences"),
                                        applicationSupportDirectory: root.appendingPathComponent("AppSupport"),
                                        configDirectory: root.appendingPathComponent("config"),
                                        homeDirectory: root.appendingPathComponent("home"),
                                        temporaryDirectory: root.appendingPathComponent("tmp"))
        for dir in [paths.preferencesDirectory, paths.applicationSupportDirectory, paths.configDirectory,
                    paths.homeDirectory, paths.temporaryDirectory] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func plistURL(_ domain: String) -> URL {
        return paths.preferencesDirectory.appendingPathComponent(domain + ".plist")
    }

    private func writeDomain(_ domain: String, _ values: [String: Any]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        try data.write(to: plistURL(domain))
    }

    private func readDomain(_ domain: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: plistURL(domain)) else {
            return nil
        }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    // The files and folders a test host using this suite creates.
    private func stateURLs(_ suite: String) -> [URL] {
        return [plistURL(suite),
                plistURL(suite + ".private"),
                paths.applicationSupportDirectory.appendingPathComponent(suite),
                paths.configDirectory.appendingPathComponent(suite),
                paths.homeDirectory.appendingPathComponent("." + suite),
                paths.temporaryDirectory.appendingPathComponent("iTerm2.instance.\(suite).lock")]
    }

    private func makeState(_ suite: String) throws {
        let urls = stateURLs(suite)
        try writeDomain(suite, ["Key": "value"])
        try writeDomain(suite + ".private", ["Key": "value"])
        for dir in urls[2..<5] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try Data().write(to: urls[5])
    }

    private func stateExists(_ suite: String) -> [Bool] {
        return stateURLs(suite).map { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func suiteName(pid: pid_t = 4242, isAlive: (pid_t) -> Bool) -> String {
        return TestHostIsolation.suiteName(forBase: base, pid: pid, nonce: 7, paths: paths, isAlive: isAlive)
    }

    func testRunningTestHostUsesItsOwnSuite() throws {
        let suite = try XCTUnwrap(iTermUserDefaults.customSuiteName())
        XCTAssertTrue(suite.hasPrefix("iterm2-tests.\(getpid())-"), suite)
    }

    func testIsTestHost() {
        XCTAssertTrue(TestHostIsolation.isTestHost(environment: ["XCInjectBundleInto": "x"]))
        XCTAssertTrue(TestHostIsolation.isTestHost(environment: ["XCInjectBundle": "x"]))
        XCTAssertFalse(TestHostIsolation.isTestHost(environment: ["HOME": "/"]))
    }

    func testSeedsFromBaseDomainWithoutChangingIt() throws {
        try writeDomain(base, ["Seeded": 1])
        try writeDomain(base + ".private", ["PrivateSeeded": 2])
        let baseBefore = try Data(contentsOf: plistURL(base))

        let suite = suiteName { _ in true }

        XCTAssertEqual(suite, "iterm2-tests.4242-7")
        XCTAssertEqual(readDomain(suite)?["Seeded"] as? Int, 1)
        XCTAssertEqual(readDomain(suite + ".private")?["PrivateSeeded"] as? Int, 2)
        XCTAssertEqual(try Data(contentsOf: plistURL(base)), baseBefore)
    }

    func testWithoutBaseDomainStartsEmpty() {
        let suite = suiteName { _ in true }
        XCTAssertNil(readDomain(suite))
    }

    func testRemovesStateOfDeadTestHostsOnly() throws {
        try makeState("iterm2-tests.111-1")
        try makeState("iterm2-tests.222-2")

        _ = suiteName { $0 == 222 }

        XCTAssertEqual(stateExists("iterm2-tests.111-1"), [false, false, false, false, false, false])
        XCTAssertEqual(stateExists("iterm2-tests.222-2"), [true, true, true, true, true, true])
    }

    // Only names of the exact form base.<pid>-<nonce> belong to a test host.
    func testLeavesOtherSuitesAlone() throws {
        let others = [base, "iterm2-tests.111", "iterm2-tests.abc-1", "iterm2-testsx.111-1",
                      "iterm2-tests.111-1-2", "iterm2-tests.111-"]
        for suite in others {
            try makeState(suite)
        }

        _ = suiteName { _ in false }

        for suite in others {
            XCTAssertEqual(stateExists(suite), [true, true, true, true, true, true], suite)
        }
    }
}
