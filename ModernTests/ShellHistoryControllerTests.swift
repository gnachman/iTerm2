//
//  ShellHistoryControllerTests.swift
//  iTerm2
//
//  Ported from the legacy iTermShellHistoryTest.m. Exercises the Core Data
//  backed command and directory history in iTermShellHistoryController.
//
//  Every test gets its own controller whose files live in a unique temporary
//  directory (via a pathForFileNamed: override), so the user's real
//  ShellHistory.sqlite and the shared instance are never touched. Whether the
//  store is on disk or in RAM is controlled by the
//  kPreferenceKeySavePasteAndCommandHistory preference, which each test sets
//  explicitly and tearDown restores.
//

import XCTest
@testable import iTerm2SharedARC

private let defaultTime: TimeInterval = 10_000_000
private let ninetyDays: TimeInterval = 60 * 60 * 24 * 90
private let databasePrefix = "test_command_history.sqlite"

// Set by -addCommand:... to advertise shell integration. Restored by tearDown.
private let hasEverBeenUsedKey = "NoSyncCommandHistoryHasEverBeenUsed"

private final class TestShellHistoryController: iTermShellHistoryController {
    private let directory: String
    var currentTime: TimeInterval = defaultTime

    init?(directory: String) {
        self.directory = directory
        super.init(partially: ())
        if !finishInitialization() {
            return nil
        }
    }

    override func path(forFileNamed name: String!) -> String! {
        guard let name = name else {
            return directory
        }
        return (directory as NSString).appendingPathComponent(name)
    }

    override func databaseFilenamePrefix() -> String! {
        return databasePrefix
    }

    override func now() -> TimeInterval {
        return currentTime
    }
}

final class ShellHistoryControllerTests: XCTestCase {
    private var directory: String!
    private var savedSaveToDisk: Any?
    private var savedHasEverBeenUsed: Any?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShellHistoryControllerTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directory = url.path

        // Read the raw stored value (nil when unset) so tearDown removes the key rather than
        // persisting the default into the suite's defaults domain.
        savedSaveToDisk = iTermUserDefaults.userDefaults().object(forKey: kPreferenceKeySavePasteAndCommandHistory)
        savedHasEverBeenUsed = iTermUserDefaults.userDefaults().object(forKey: hasEverBeenUsedKey)
        setSavesToDisk(true)
    }

    override func tearDownWithError() throws {
        iTermPreferences.setObject(savedSaveToDisk, forKey: kPreferenceKeySavePasteAndCommandHistory)
        if let saved = savedHasEverBeenUsed {
            iTermUserDefaults.userDefaults().set(saved, forKey: hasEverBeenUsedKey)
        } else {
            iTermUserDefaults.userDefaults().removeObject(forKey: hasEverBeenUsedKey)
        }
        if let directory = directory {
            try? FileManager.default.removeItem(atPath: directory)
        }
        directory = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func setSavesToDisk(_ value: Bool) {
        iTermPreferences.setBool(value, forKey: kPreferenceKeySavePasteAndCommandHistory)
    }

    private func makeController(file: StaticString = #filePath, line: UInt = #line) throws -> TestShellHistoryController {
        return try XCTUnwrap(TestShellHistoryController(directory: directory), file: file, line: line)
    }

    private func makeHost(_ username: String = "user1", _ hostname: String = "host1") -> VT100RemoteHost {
        return VT100RemoteHost(username: username, hostname: hostname)
    }

    @discardableResult
    private func addCommand(_ command: String,
                            to controller: TestShellHistoryController,
                            host: VT100RemoteHost,
                            directory: String = "/directory1",
                            mark: VT100ScreenMark = VT100ScreenMark()) -> VT100ScreenMark {
        controller.addCommand(command, onHost: host, inDirectory: directory, withMark: mark)
        return mark
    }

    private func entries(_ controller: TestShellHistoryController,
                         prefix: String = "",
                         host: VT100RemoteHost) -> [iTermCommandHistoryEntryMO] {
        return controller.commandHistoryEntries(withPrefix: prefix, onHost: host) ?? []
    }

    private func uses(of entry: iTermCommandHistoryEntryMO,
                      file: StaticString = #filePath, line: UInt = #line) throws -> [iTermCommandHistoryCommandUseMO] {
        return try XCTUnwrap(entry.uses?.array as? [iTermCommandHistoryCommandUseMO], file: file, line: line)
    }

    private func directories(_ controller: TestShellHistoryController,
                             host: VT100RemoteHost) -> [iTermRecentDirectoryMO] {
        return controller.directoriesSortedByScore(onHost: host) as? [iTermRecentDirectoryMO] ?? []
    }

    private let commandsWithCommonPrefixes = ["abc", "abcd", "a", "bcd", "", "abc"]

    // Adds commandsWithCommonPrefixes at times 0...5 on the returned host, plus
    // one command on an unrelated host.
    private func addEntriesWithCommonPrefixes(_ controller: TestShellHistoryController) -> VT100RemoteHost {
        let host = makeHost()
        XCTAssertEqual(entries(controller, host: host).count, 0)

        controller.currentTime = 0
        for command in commandsWithCommonPrefixes {
            addCommand(command, to: controller, host: host)
            controller.currentTime += 1
        }
        addCommand("aaaa", to: controller, host: makeHost("bogus", "bogus"))
        return host
    }

    // MARK: - Command History

    func testAddFirstCommandOnNewHostCreatesEntry() throws {
        let controller = try makeController()
        let now: TimeInterval = 1_000_000
        controller.currentTime = now
        let host = makeHost()
        XCTAssertEqual(entries(controller, host: host).count, 0)

        addCommand("command1", to: controller, host: host)

        let found = entries(controller, host: host)
        XCTAssertEqual(found.count, 1)
        let entry = try XCTUnwrap(found.first)
        XCTAssertEqual(entry.command, "command1")
        XCTAssertEqual(entry.numberOfUses, 1)
        XCTAssertEqual(entry.timeOfLastUse, NSNumber(value: now))
        XCTAssertEqual(entry.uses?.count, 1)
        XCTAssertEqual(entry.remoteHost?.hostname, host.hostname)
        XCTAssertEqual(entry.remoteHost?.username, host.username)
    }

    func testAddFirstCommandOnNewHostRecordsUse() throws {
        let controller = try makeController()
        let now: TimeInterval = 1_000_000
        controller.currentTime = now
        let host = makeHost()

        let mark = addCommand("command1", to: controller, host: host)

        let entry = try XCTUnwrap(entries(controller, host: host).first)
        let use = try XCTUnwrap(uses(of: entry).first)
        XCTAssertEqual(use.markGuid, mark.guid)
        XCTAssertEqual(use.directory, "/directory1")
        XCTAssertEqual(use.time, NSNumber(value: now))
        XCTAssertEqual(use.command, "command1")
        XCTAssertNil(use.code)
        XCTAssertEqual(use.entry, entry)
    }

    func testAddAdditionalUseOfCommandUpdatesEntry() throws {
        let controller = try makeController()
        let time1: TimeInterval = 1_000_000
        let time2: TimeInterval = 1_000_001
        let host = makeHost()

        controller.currentTime = time1
        addCommand("command1", to: controller, host: host, directory: "/directory1")
        XCTAssertEqual(entries(controller, host: host).count, 1)

        controller.currentTime = time2
        addCommand("command1", to: controller, host: host, directory: "/directory2")

        let found = entries(controller, host: host)
        XCTAssertEqual(found.count, 1)
        let entry = try XCTUnwrap(found.first)
        XCTAssertEqual(entry.command, "command1")
        XCTAssertEqual(entry.numberOfUses, 2)
        XCTAssertEqual(entry.timeOfLastUse, NSNumber(value: time2))
        XCTAssertEqual(entry.uses?.count, 2)
        XCTAssertEqual(entry.remoteHost?.hostname, host.hostname)
        XCTAssertEqual(entry.remoteHost?.username, host.username)
    }

    func testAddAdditionalUseOfCommandKeepsBothUsesInOrder() throws {
        let controller = try makeController()
        let time1: TimeInterval = 1_000_000
        let time2: TimeInterval = 1_000_001
        let host = makeHost()

        controller.currentTime = time1
        let mark1 = addCommand("command1", to: controller, host: host, directory: "/directory1")
        controller.currentTime = time2
        let mark2 = addCommand("command1", to: controller, host: host, directory: "/directory2")

        let entry = try XCTUnwrap(entries(controller, host: host).first)
        let found = try uses(of: entry)
        XCTAssertEqual(found.count, 2)

        XCTAssertEqual(found[0].markGuid, mark1.guid)
        XCTAssertEqual(found[0].directory, "/directory1")
        XCTAssertEqual(found[0].time, NSNumber(value: time1))
        XCTAssertEqual(found[0].command, "command1")
        XCTAssertNil(found[0].code)
        XCTAssertEqual(found[0].entry, entry)

        XCTAssertEqual(found[1].markGuid, mark2.guid)
        XCTAssertEqual(found[1].directory, "/directory2")
        XCTAssertEqual(found[1].time, NSNumber(value: time2))
        XCTAssertEqual(found[1].command, "command1")
        XCTAssertNil(found[1].code)
        XCTAssertEqual(found[1].entry, entry)
    }

    func testSetStatusOfCommandRecordsExitCode() throws {
        let controller = try makeController()
        let now: TimeInterval = 1_000_000
        controller.currentTime = now
        let host = makeHost()

        let mark = addCommand("command1", to: controller, host: host)
        let initialUse = try XCTUnwrap(uses(of: try XCTUnwrap(entries(controller, host: host).first)).first)
        XCTAssertNil(initialUse.code)

        controller.setStatusOfCommandAtMark(mark, onHost: host, to: 123)

        let found = entries(controller, host: host)
        XCTAssertEqual(found.count, 1)
        let entry = try XCTUnwrap(found.first)
        let use = try XCTUnwrap(uses(of: entry).first)
        XCTAssertEqual(use.markGuid, mark.guid)
        XCTAssertEqual(use.directory, "/directory1")
        XCTAssertEqual(use.time, NSNumber(value: now))
        XCTAssertEqual(use.command, "command1")
        XCTAssertEqual(use.code, 123)
        XCTAssertEqual(use.entry, entry)
    }

    func testSearchCommandEntriesWithEmptyPrefixReturnsUniqueCommands() throws {
        let controller = try makeController()
        let host = addEntriesWithCommonPrefixes(controller)
        // "abc" was added twice, so there is one fewer entry than command.
        XCTAssertEqual(entries(controller, host: host).count, commandsWithCommonPrefixes.count - 1)
    }

    func testSearchCommandEntriesByPrefixA() throws {
        let controller = try makeController()
        let host = addEntriesWithCommonPrefixes(controller)
        XCTAssertEqual(entries(controller, prefix: "a", host: host).count, 3)
    }

    func testSearchCommandEntriesByPrefixB() throws {
        let controller = try makeController()
        let host = addEntriesWithCommonPrefixes(controller)
        XCTAssertEqual(entries(controller, prefix: "b", host: host).count, 1)
    }

    func testSearchCommandEntriesByPrefixWithNoMatches() throws {
        let controller = try makeController()
        let host = addEntriesWithCommonPrefixes(controller)
        XCTAssertEqual(entries(controller, prefix: "c", host: host).count, 0)
    }

    func testAutocompleteSuggestionsWithEmptyPrefixReturnMostRecentUses() throws {
        let controller = try makeController()
        let host = addEntriesWithCommonPrefixes(controller)
        let suggestions = controller.autocompleteSuggestions(withPartialCommand: "", onHost: host) ?? []
        XCTAssertEqual(suggestions.count, commandsWithCommonPrefixes.count - 1)
        // "abc" was used at times 0 and 5; the suggestion must be its latest use.
        let abc = try XCTUnwrap(suggestions.first { $0.command == "abc" })
        XCTAssertEqual(abc.time?.doubleValue, 5)
    }

    func testAutocompleteSuggestionsByPrefixA() throws {
        let controller = try makeController()
        let host = addEntriesWithCommonPrefixes(controller)
        XCTAssertEqual(controller.autocompleteSuggestions(withPartialCommand: "a", onHost: host)?.count, 3)
    }

    func testAutocompleteSuggestionsByPrefixB() throws {
        let controller = try makeController()
        let host = addEntriesWithCommonPrefixes(controller)
        XCTAssertEqual(controller.autocompleteSuggestions(withPartialCommand: "b", onHost: host)?.count, 1)
    }

    func testAutocompleteSuggestionsByPrefixWithNoMatches() throws {
        let controller = try makeController()
        let host = addEntriesWithCommonPrefixes(controller)
        XCTAssertEqual(controller.autocompleteSuggestions(withPartialCommand: "c", onHost: host)?.count, 0)
    }

    func testHaveCommandsForHost() throws {
        let controller = try makeController()
        let host = makeHost()
        XCTAssertFalse(controller.haveCommands(forHost: host))

        addCommand("command", to: controller, host: host, directory: "directory")

        XCTAssertTrue(controller.haveCommands(forHost: host))
    }

    func testEraseCommandHistoryForHostLeavesOtherHostsAlone() throws {
        let controller = try makeController()
        let host1 = makeHost("user1", "host1")
        let host2 = makeHost("user2", "host2")
        addCommand("command", to: controller, host: host1, directory: "directory")
        addCommand("command", to: controller, host: host2, directory: "directory")
        XCTAssertTrue(controller.haveCommands(forHost: host1))
        XCTAssertTrue(controller.haveCommands(forHost: host2))

        controller.eraseCommandHistory(forHost: host1)

        XCTAssertFalse(controller.haveCommands(forHost: host1))
        XCTAssertEqual(controller.commandUses(forHost: host1)?.count, 0)
        XCTAssertTrue(controller.haveCommands(forHost: host2))
        XCTAssertEqual(controller.commandUses(forHost: host2)?.count, 1)
    }

    func testEraseCommandHistoryForHostPersistsAcrossReload() throws {
        let host1 = makeHost("user1", "host1")
        let host2 = makeHost("user2", "host2")
        try autoreleasepool {
            let controller = try makeController()
            addCommand("command", to: controller, host: host1, directory: "directory")
            addCommand("command", to: controller, host: host2, directory: "directory")
            controller.eraseCommandHistory(forHost: host1)
        }

        let reloaded = try makeController()
        XCTAssertFalse(reloaded.haveCommands(forHost: host1))
        XCTAssertTrue(reloaded.haveCommands(forHost: host2))
    }

    func testEraseCommandHistoryWhenSavingToDiskClearsHost() throws {
        let controller = try makeController()
        let host = makeHost()
        addCommand("command", to: controller, host: host, directory: "directory")
        XCTAssertTrue(controller.haveCommands(forHost: host))

        controller.eraseCommandHistory(true, directories: false)

        XCTAssertFalse(controller.haveCommands(forHost: host))
        XCTAssertEqual(controller.commandUses(forHost: host)?.count, 0)
    }

    func testEraseCommandHistoryWhenSavingToDiskPersistsAcrossReload() throws {
        let host = makeHost()
        try autoreleasepool {
            let controller = try makeController()
            addCommand("command", to: controller, host: host, directory: "directory")
            controller.eraseCommandHistory(true, directories: false)
        }

        let reloaded = try makeController()
        XCTAssertFalse(reloaded.haveCommands(forHost: host))
    }

    func testEraseCommandHistoryInMemoryOnly() throws {
        setSavesToDisk(false)
        let controller = try makeController()
        let host = makeHost()
        addCommand("command", to: controller, host: host, directory: "directory")
        XCTAssertTrue(controller.haveCommands(forHost: host))

        controller.eraseCommandHistory(true, directories: false)

        XCTAssertFalse(controller.haveCommands(forHost: host))
    }

    func testFindCommandUseByMark() throws {
        let controller = try makeController()
        controller.currentTime = 1_000_000
        let host = makeHost()
        XCTAssertEqual(entries(controller, host: host).count, 0)

        addCommand("command1", to: controller, host: host, directory: "/directory1")
        let mark = addCommand("command1", to: controller, host: host, directory: "/directory2")
        addCommand("command1", to: controller, host: host, directory: "/directory3")
        addCommand("command2", to: controller, host: host, directory: "/directory3")

        let use = try XCTUnwrap(controller.commandUse(withMarkGuid: mark.guid, onHost: host))
        XCTAssertEqual(use.directory, "/directory2")
    }

    func testGetAllCommandUsesForHost() throws {
        let controller = try makeController()
        let host = addEntriesWithCommonPrefixes(controller)
        XCTAssertEqual(controller.commandUses(forHost: host)?.count, commandsWithCommonPrefixes.count)
    }

    func testOldCommandUsesRemovedOnReload() throws {
        let host = makeHost()
        try autoreleasepool {
            let controller = try makeController()

            // Just old enough to be removed.
            controller.currentTime = defaultTime - (ninetyDays + 1)
            addCommand("command1", to: controller, host: host, directory: "directory")

            // Should stay.
            controller.currentTime = defaultTime
            addCommand("command2", to: controller, host: host, directory: "directory")

            XCTAssertEqual(entries(controller, host: host).count, 2)
        }

        // The new controller's clock reads defaultTime, so the old use is purged on load.
        let reloaded = try makeController()
        let found = entries(reloaded, host: host)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.command, "command2")
    }

    // MARK: - Generic

    func testCorruptDatabaseIsDiscardedAndRecreated() throws {
        let host: VT100RemoteHost = try autoreleasepool {
            let controller = try makeController()
            let host = addEntriesWithCommonPrefixes(controller)
            addCommand("command", to: controller, host: host, directory: "directory")
            XCTAssertTrue(controller.haveCommands(forHost: host))
            return host
        }

        // Scribble over every database file (main file plus any journal).
        let fileManager = FileManager.default
        let databaseFiles = try fileManager.contentsOfDirectory(atPath: directory).filter {
            $0.hasPrefix(databasePrefix)
        }
        XCTAssertFalse(databaseFiles.isEmpty)
        for name in databaseFiles {
            let path = (directory as NSString).appendingPathComponent(name)
            var data = try Data(contentsOf: URL(fileURLWithPath: path))
            var i = 1024
            while i < data.count {
                data[i] = UInt8(i & 0xff)
                i += 16
            }
            try data.write(to: URL(fileURLWithPath: path))
        }

        let reloaded = try makeController()
        XCTAssertFalse(reloaded.haveCommands(forHost: host))
        addCommand("command", to: reloaded, host: host, directory: "directory")
        XCTAssertTrue(reloaded.haveCommands(forHost: host))
    }

    func testInMemoryStoreIsEvanescent() throws {
        setSavesToDisk(false)
        let host = makeHost()
        try autoreleasepool {
            let controller = try makeController()
            addCommand("command", to: controller, host: host, directory: "directory")
            XCTAssertTrue(controller.haveCommands(forHost: host))
        }

        let reloaded = try makeController()
        XCTAssertFalse(reloaded.haveCommands(forHost: host))
    }

    // MARK: - Directories

    func testAddFirstDirectoryToNewHost() throws {
        let controller = try makeController()
        let now: TimeInterval = 1_000_000
        controller.currentTime = now
        let host = makeHost()
        XCTAssertEqual(directories(controller, host: host).count, 0)

        controller.recordUse(ofPath: "/test/path", onHost: host, isChange: true)

        let found = directories(controller, host: host)
        XCTAssertEqual(found.count, 1)
        let directory = try XCTUnwrap(found.first)
        XCTAssertEqual(directory.path, "/test/path")
        XCTAssertEqual(directory.useCount, 1)
        XCTAssertEqual(directory.lastUse, NSNumber(value: now))
        XCTAssertEqual(directory.starred?.boolValue, false)
        XCTAssertEqual(directory.remoteHost?.hostname, host.hostname)
        XCTAssertEqual(directory.remoteHost?.username, host.username)
    }

    func testReuseDirectory() throws {
        let controller = try makeController()
        let host = makeHost()
        XCTAssertEqual(directories(controller, host: host).count, 0)

        controller.currentTime = 500
        controller.recordUse(ofPath: "/test/path", onHost: host, isChange: true)
        let now: TimeInterval = 1000
        controller.currentTime = now
        controller.recordUse(ofPath: "/test/path", onHost: host, isChange: true)

        let found = directories(controller, host: host)
        XCTAssertEqual(found.count, 1)
        let directory = try XCTUnwrap(found.first)
        XCTAssertEqual(directory.path, "/test/path")
        XCTAssertEqual(directory.useCount, 2)
        XCTAssertEqual(directory.lastUse, NSNumber(value: now))
        XCTAssertEqual(directory.starred?.boolValue, false)
        XCTAssertEqual(directory.remoteHost?.hostname, host.hostname)
        XCTAssertEqual(directory.remoteHost?.username, host.username)
    }

    func testSetDirectoryStarred() throws {
        let controller = try makeController()
        let host = makeHost()
        controller.recordUse(ofPath: "/test/path", onHost: host, isChange: true)
        let directory = try XCTUnwrap(directories(controller, host: host).first)

        controller.setDirectory(directory, starred: true)

        let found = directories(controller, host: host)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.starred, true)
    }

    func testSetDirectoryUnstarred() throws {
        let controller = try makeController()
        let host = makeHost()
        controller.recordUse(ofPath: "/test/path", onHost: host, isChange: true)
        let directory = try XCTUnwrap(directories(controller, host: host).first)
        controller.setDirectory(directory, starred: true)
        XCTAssertEqual(directories(controller, host: host).first?.starred, true)

        controller.setDirectory(directory, starred: false)

        let found = directories(controller, host: host)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.starred, false)
    }

    func testAbbreviationSafeIndexes() throws {
        let controller = try makeController()
        let host = makeHost()
        let paths = ["/a1/b1/c1/d1/e1/f1",
                     "/a1/b1/c2/d1/e1/f1",  // Can't abbreviate c1/c2
                     "/a1/b1/c1/d1/e2"]  // Can't abbreviate e1/e2
        for path in paths {
            controller.recordUse(ofPath: path, onHost: host, isChange: true)
        }

        let found = directories(controller, host: host)
        XCTAssertEqual(found.count, 3)
        let directory = try XCTUnwrap(found.first { $0.path == paths[0] })

        let actual = controller.abbreviationSafeIndexes(inRecentDirectory: directory)
        let expected = NSMutableIndexSet()
        expected.add(0)
        expected.add(1)
        expected.add(3)
        expected.add(5)
        XCTAssertEqual(actual, expected as IndexSet)
    }

    func testSortDirectoriesByScore() throws {
        let controller = try makeController()
        let host = makeHost()

        // Directories sort by: starred, int(log2(useCount)), lastUseDate.
        for starred in [true, false] {
            for useCount in [1, 8, 16] {
                for date in [1, 2] {
                    controller.currentTime = TimeInterval(date)
                    let path = "/\(starred ? "starred" : "unstarred")/uses\(useCount)/date\(date)"
                    for i in 0..<useCount {
                        let directory = controller.recordUse(ofPath: path, onHost: host, isChange: true)
                        if starred && i == 0 {
                            controller.setDirectory(directory, starred: true)
                        }
                    }
                }
            }
        }

        // Number of uses will be considered equivalent for these so they'll sort by date.
        controller.currentTime = 2
        for _ in 0..<9 {
            controller.recordUse(ofPath: "/unstarred/uses9/date2", onHost: host, isChange: true)
        }
        controller.currentTime = 1
        for _ in 0..<10 {
            controller.recordUse(ofPath: "/unstarred/uses10/date1", onHost: host, isChange: true)
        }

        let expected = ["/starred/uses16/date2",
                        "/starred/uses16/date1",
                        "/starred/uses8/date2",
                        "/starred/uses8/date1",
                        "/starred/uses1/date2",
                        "/starred/uses1/date1",
                        "/unstarred/uses16/date2",
                        "/unstarred/uses16/date1",
                        "/unstarred/uses9/date2",
                        "/unstarred/uses8/date2",
                        "/unstarred/uses10/date1",
                        "/unstarred/uses8/date1",
                        "/unstarred/uses1/date2",
                        "/unstarred/uses1/date1"]
        let actual = directories(controller, host: host).map { $0.path ?? "" }
        XCTAssertEqual(actual, expected)
    }

    func testHaveDirectoriesForHost() throws {
        let controller = try makeController()
        let host = makeHost()
        XCTAssertFalse(controller.haveDirectories(forHost: host))

        controller.recordUse(ofPath: "/test/path", onHost: host, isChange: true)

        XCTAssertTrue(controller.haveDirectories(forHost: host))
    }

    func testHaveDirectoriesForHostPersistsAcrossReload() throws {
        let host = makeHost()
        try autoreleasepool {
            let controller = try makeController()
            controller.recordUse(ofPath: "/test/path", onHost: host, isChange: true)
            XCTAssertTrue(controller.haveDirectories(forHost: host))
        }

        let reloaded = try makeController()
        XCTAssertTrue(reloaded.haveDirectories(forHost: host))
    }

    // MARK: - Backing store changes

    func testSwitchingBackingStoreFromDiskToRAMKeepsData() throws {
        let controller = try makeController()
        let host = makeHost()
        controller.recordUse(ofPath: "/test/path", onHost: host, isChange: true)
        addCommand("command1", to: controller, host: host)
        XCTAssertTrue(controller.haveDirectories(forHost: host))
        XCTAssertTrue(controller.haveCommands(forHost: host))

        setSavesToDisk(false)
        controller.backingStoreTypeDidChange()

        XCTAssertTrue(controller.haveDirectories(forHost: host))
        XCTAssertTrue(controller.haveCommands(forHost: host))
    }

    func testSwitchingBackingStoreBackAndForthKeepsData() throws {
        let controller = try makeController()
        let host = makeHost()
        let mark = VT100ScreenMark()
        controller.recordUse(ofPath: "/test/path", onHost: host, isChange: true)
        addCommand("command1", to: controller, host: host, mark: mark)

        // Initial value is saved to disk. Flip it to RAM. Should lose no data.
        setSavesToDisk(false)
        controller.backingStoreTypeDidChange()
        XCTAssertTrue(controller.haveDirectories(forHost: host))
        XCTAssertTrue(controller.haveCommands(forHost: host))

        controller.recordUse(ofPath: "/test2/path2", onHost: host, isChange: true)
        addCommand("command1", to: controller, host: host, mark: mark)

        // Back to disk. Should lose no data.
        setSavesToDisk(true)
        controller.backingStoreTypeDidChange()
        XCTAssertTrue(controller.haveDirectories(forHost: host))
        XCTAssertTrue(controller.haveCommands(forHost: host))

        // Back to RAM.
        setSavesToDisk(false)
        controller.backingStoreTypeDidChange()
        XCTAssertTrue(controller.haveDirectories(forHost: host))
        XCTAssertTrue(controller.haveCommands(forHost: host))

        // Back to disk.
        setSavesToDisk(true)
        controller.backingStoreTypeDidChange()
        XCTAssertTrue(controller.haveDirectories(forHost: host))
        XCTAssertTrue(controller.haveCommands(forHost: host))
    }
}
