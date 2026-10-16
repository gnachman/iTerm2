//
//  PasswordArchiveTests.swift
//  iTerm2
//
//  Created by George Nachman on 10/12/26.
//

import XCTest
@testable import iTerm2SharedARC

final class PasswordArchiveTests: XCTestCase {
    private let iterations: UInt32 = 1000
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".iterm2passwords")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    private func write(_ entries: [PasswordArchiveEntry], passphrase: String = "correct horse") throws {
        try PasswordArchive.write(entries, to: url, passphrase: passphrase, iterations: iterations)
    }

    private func read(passphrase: String = "correct horse") throws -> [PasswordArchiveEntry] {
        return try PasswordArchive.read(from: url, passphrase: passphrase, minimumIterations: iterations)
    }

    private func entry(_ accountName: String,
                       _ userName: String = "",
                       _ password: String = "pw",
                       scope: PasswordArchiveScope = .terminal) -> PasswordArchiveEntry {
        return PasswordArchiveEntry(scope: scope, accountName: accountName, userName: userName, password: password)
    }

    func testRoundTrip() throws {
        let entries = [entry("github", "george", "s3cret"),
                       entry("example.com", "", "", scope: .browser),
                       // The keychain separates account and user names with an en-space em-dash
                       // en-space, so make sure those survive inside a name.
                       entry("weird\u{2002}—\u{2002}name ✓", "ユーザー", "pässwörd")]
        try write(entries)
        XCTAssertEqual(try read(), entries)
    }

    func testEmptyRoundTrip() throws {
        try write([])
        XCTAssertEqual(try read(), [])
    }

    func testWrongPassphrase() throws {
        try write([entry("a")])
        XCTAssertThrowsError(try read(passphrase: "nope")) { error in
            XCTAssertEqual(error as? PasswordArchiveError, .wrongPassphraseOrDamaged)
        }
    }

    func testNotAnArchive() throws {
        try Data("hello".utf8).write(to: url)
        XCTAssertThrowsError(try read()) { error in
            XCTAssertEqual(error as? PasswordArchiveError, .notAPasswordArchive)
        }
    }

    // Checked before asking for a passphrase.
    func testCheck() throws {
        try write([entry("a")])
        XCTAssertNoThrow(try PasswordArchive.check(url))
        try Data("hello".utf8).write(to: url)
        XCTAssertThrowsError(try PasswordArchive.check(url)) { error in
            XCTAssertEqual(error as? PasswordArchiveError, .notAPasswordArchive)
        }
    }

    func testNewerPayloadVersion() throws {
        let json = Data(#"{"version": 2, "entries": [], "somethingNew": true}"#.utf8)
        let encryption = try XCTUnwrap(SIGArchivePassphraseEncryption(passphrase: "correct horse",
                                                                      cipher: SIGArchiveAESGCMCipher(),
                                                                      iterations: iterations))
        try SIGArchiveBuilder(payloadData: json, identity: nil, encryption: encryption).write(to: url)
        XCTAssertThrowsError(try read()) { error in
            XCTAssertEqual(error as? PasswordArchiveError, .unsupportedVersion)
        }
    }

    // MARK: - Export logic

    private struct UnreadableStore: PasswordArchiveStore {
        struct Account: PasswordArchiveStoreAccount {
            let accountName = "example.com"
            let userName = "alice"
            func password() throws -> String { throw PasswordArchiveError.keychain("boom") }
            func setPassword(_ password: String) throws {}
        }

        func accounts(scope: PasswordArchiveScope) throws -> [PasswordArchiveStoreAccount] { [Account()] }
        func add(_ entry: PasswordArchiveEntry) throws {}
    }

    // An unreadable password must say which entry it belongs to, so the user can find it.
    func testExportErrorNamesTheEntry() throws {
        XCTAssertThrowsError(try PasswordArchiveExporter.entries(scopes: [.terminal], store: UnreadableStore())) { error in
            guard case let .readPassword(accountName, userName, reason) = error as? PasswordArchiveError else {
                return XCTFail("Unexpected error \(error)")
            }
            XCTAssertEqual(accountName, "example.com")
            XCTAssertEqual(userName, "alice")
            XCTAssertTrue(reason.contains("boom"))
        }
    }

    // MARK: - Import logic

    private final class MemoryStore: PasswordArchiveStore {
        final class Account: PasswordArchiveStoreAccount {
            let accountName: String
            let userName: String
            var storedPassword: String

            init(_ accountName: String, _ userName: String, _ password: String) {
                self.accountName = accountName
                self.userName = userName
                self.storedPassword = password
            }

            func password() throws -> String { storedPassword }
            func setPassword(_ password: String) throws { storedPassword = password }
        }

        var accountsByScope = [PasswordArchiveScope: [Account]]()
        var failOnAdd: String?

        func accounts(scope: PasswordArchiveScope) throws -> [PasswordArchiveStoreAccount] {
            return accountsByScope[scope] ?? []
        }

        func add(_ entry: PasswordArchiveEntry) throws {
            if entry.accountName == failOnAdd {
                throw PasswordArchiveError.keychain("boom")
            }
            accountsByScope[entry.scope, default: []].append(Account(entry.accountName, entry.userName, entry.password))
        }

        func password(_ accountName: String, _ userName: String = "", scope: PasswordArchiveScope = .terminal) -> String? {
            let matches = (accountsByScope[scope] ?? []).filter { $0.accountName == accountName && $0.userName == userName }
            XCTAssertLessThanOrEqual(matches.count, 1)
            return matches.first?.storedPassword
        }
    }

    private func storeWithExisting(_ names: [String]) -> MemoryStore {
        let store = MemoryStore()
        for name in names {
            try! store.add(entry(name, "", "old"))
        }
        return store
    }

    private func importer(_ store: MemoryStore,
                          scopes: Set<PasswordArchiveScope> = Set(PasswordArchiveScope.allCases)) -> PasswordArchiveImporter {
        return PasswordArchiveImporter(store: store, scopesUsingKeychain: scopes)
    }

    // A scope whose password manager isn't the Keychain gets nothing written to its keychain store.
    func testEntriesForScopesNotUsingKeychainAreNotImported() throws {
        let store = MemoryStore()
        let summary = try importer(store, scopes: [.browser]).run([entry("a"), entry("b", scope: .browser), entry("c")]) { _ in
            XCTFail("Unexpected conflict")
            return .cancel
        }
        XCTAssertEqual(summary, PasswordArchiveImporter.Summary(added: 1, notImported: 2))
        XCTAssertNil(store.password("a"))
        XCTAssertEqual(store.password("b", scope: .browser), "pw")
    }

    func testNewEntriesAreAddedWithoutAsking() throws {
        let store = MemoryStore()
        let summary = try importer(store).run([entry("a"), entry("b", scope: .browser)]) { _ in
            XCTFail("Unexpected conflict")
            return .cancel
        }
        XCTAssertEqual(summary, PasswordArchiveImporter.Summary(added: 2))
        XCTAssertEqual(store.password("a"), "pw")
        XCTAssertEqual(store.password("b", scope: .browser), "pw")
    }

    // The same account name in a different scope, or with a different user name, isn't a conflict.
    func testConflictsMatchScopeAccountAndUser() throws {
        let store = storeWithExisting(["a"])
        let summary = try importer(store).run([entry("a", scope: .browser), entry("a", "someone")]) { _ in
            XCTFail("Unexpected conflict")
            return .cancel
        }
        XCTAssertEqual(summary.added, 2)
    }

    func testReplaceAndSkipAskEachTime() throws {
        let store = storeWithExisting(["a", "b", "c"])
        var answers: [PasswordArchiveImporter.ConflictDecision] = [.replace, .skip, .replace]
        var asked = [String]()
        let summary = try importer(store).run([entry("a", "", "new"), entry("b", "", "new"), entry("c", "", "new")]) {
            asked.append($0.accountName)
            return answers.removeFirst()
        }
        XCTAssertEqual(asked, ["a", "b", "c"])
        XCTAssertEqual(summary, PasswordArchiveImporter.Summary(replaced: 2, skipped: 1))
        XCTAssertEqual(store.password("a"), "new")
        XCTAssertEqual(store.password("b"), "old")
        XCTAssertEqual(store.password("c"), "new")
    }

    func testAlwaysReplaceStopsAsking() throws {
        let store = storeWithExisting(["a", "b", "c"])
        var asked = 0
        let summary = try importer(store).run([entry("a", "", "new"), entry("b", "", "new"), entry("c", "", "new")]) { _ in
            asked += 1
            return .alwaysReplace
        }
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(summary, PasswordArchiveImporter.Summary(replaced: 3))
        XCTAssertEqual(store.password("c"), "new")
    }

    func testNeverReplaceStopsAsking() throws {
        let store = storeWithExisting(["a", "b"])
        var answers: [PasswordArchiveImporter.ConflictDecision] = [.replace, .neverReplace]
        let summary = try importer(store).run([entry("a", "", "new"), entry("b", "", "new"), entry("new-one"), entry("a", "", "newer")]) { _ in
            answers.removeFirst()
        }
        XCTAssertEqual(summary, PasswordArchiveImporter.Summary(added: 1, replaced: 1, skipped: 2))
        XCTAssertEqual(store.password("a"), "new")
        XCTAssertEqual(store.password("b"), "old")
    }

    func testCancelStopsImmediately() throws {
        let store = storeWithExisting(["b"])
        let summary = try importer(store).run([entry("a"), entry("b", "", "new"), entry("c")]) { _ in
            .cancel
        }
        XCTAssertEqual(summary, PasswordArchiveImporter.Summary(added: 1, cancelled: true))
        XCTAssertEqual(store.password("b"), "old")
        XCTAssertNil(store.password("c"))
    }

    // Re-importing an unchanged password isn't a conflict.
    func testIdenticalPasswordIsNotAConflict() throws {
        let store = storeWithExisting(["a", "b"])
        let summary = try importer(store).run([entry("a", "", "old"), entry("b", "", "new")]) {
            XCTAssertEqual($0.accountName, "b")
            return .replace
        }
        XCTAssertEqual(summary, PasswordArchiveImporter.Summary(replaced: 1, unchanged: 1))
        XCTAssertEqual(store.password("b"), "new")
    }

    // A failure partway through keeps the counts so far, since earlier entries were already written.
    func testFailurePartwayReportsWhatWasImported() throws {
        let store = storeWithExisting(["b"])
        store.failOnAdd = "c"
        let summary = try importer(store).run([entry("a"), entry("b", "", "new"), entry("c"), entry("d")]) { _ in
            .replace
        }
        XCTAssertEqual(summary.added, 1)
        XCTAssertEqual(summary.replaced, 1)
        XCTAssertEqual(summary.failure, PasswordArchiveError.keychain("boom").localizedDescription)
        XCTAssertNil(store.password("d"))
    }

    // A file holding the same account twice must not create two keychain items.
    func testDuplicateWithinFileIsAConflict() throws {
        let store = MemoryStore()
        var asked = 0
        let summary = try importer(store).run([entry("a", "", "first"), entry("a", "", "second")]) { _ in
            asked += 1
            return .replace
        }
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(summary, PasswordArchiveImporter.Summary(added: 1, replaced: 1))
        XCTAssertEqual(store.password("a"), "second")
    }
}
