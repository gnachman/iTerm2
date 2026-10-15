//
//  KeePassXCAccountNameTests.swift
//  ModernTests
//
//  keepassxc-cli treats every “/” in an entry path as a group separator and has no way to
//  escape one, so an entry titled “http://localhost:8022 (Realm)” (the name the browser’s
//  basic-auth store gives every remembered credential) could never be created. The KeePassXC
//  data source stores “/” in titles as a lookalike character and maps it back when listing.
//  These tests drive the real AdapterPasswordDataSource against a fake adapter script that
//  records the JSON requests it receives.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class KeePassXCAccountNameTests: XCTestCase {
    private var directory: URL!
    private var adapterPath: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("KeePassXCAccountNameTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        adapterPath = directory.appendingPathComponent("fake-adapter").path
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    // Writes a fake adapter that saves each request's stdin to <subcommand>.json and replies
    // with a canned response. `listedTitle` is the title list-accounts reports, as the real
    // adapter would print it from keepassxc-cli.
    private func installFakeAdapter(listedTitle: String) throws {
        let listResponse = try JSONSerialization.data(withJSONObject: [
            "accounts": [[
                "identifier": ["accountID": listedTitle],
                "userName": "qa",
                "accountName": listedTitle,
                "hasOTP": false
            ]]
        ])
        let listPath = directory.appendingPathComponent("list-response.json")
        try listResponse.write(to: listPath)
        let script = """
        #!/bin/sh
        DIR="$(dirname "$0")"
        cat > "$DIR/$1.json"
        case "$1" in
        handshake)
            echo '{"protocolVersion":0,"name":"Fake","requiresMasterPassword":false,"canSetPasswords":true,"needsPathToDatabase":false}'
            ;;
        login)
            echo '{"token":"t"}'
            ;;
        add-account)
            echo '{"accountIdentifier":{"accountID":"new-id"}}'
            ;;
        list-accounts)
            cat "$DIR/list-response.json"
            ;;
        *)
            echo '{"error":"unexpected"}'
            exit 1
            ;;
        esac
        """
        try script.write(toFile: adapterPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: adapterPath)
    }

    private func recordedRequest(_ subcommand: String) throws -> [String: Any] {
        let data = try Data(contentsOf: directory.appendingPathComponent("\(subcommand).json"))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private var uniqueIdentifier: String {
        "KeePassXCAccountNameTests-\(UUID().uuidString)"
    }

    private func add(_ dataSource: AdapterPasswordDataSource, accountName: String) -> (PasswordManagerAccount?, Error?) {
        let done = expectation(description: "add")
        var result: (PasswordManagerAccount?, Error?) = (nil, nil)
        dataSource.add(userName: "qa",
                       accountName: accountName,
                       password: "pw",
                       flags: [:],
                       context: RecipeExecutionContext(window: nil)) { account, error in
            result = (account, error)
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
        return result
    }

    private func fetch(_ dataSource: AdapterPasswordDataSource) -> [PasswordManagerAccount] {
        let done = expectation(description: "fetch")
        var result = [PasswordManagerAccount]()
        dataSource.fetchAccounts(context: RecipeExecutionContext(window: nil)) { accounts in
            result = accounts
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
        return result
    }

    private var basicAuthAccountName: String {
        iTermBrowserBasicAuthStore.accountName(scheme: "http", host: "localhost", port: 8022, realm: "QA22")
    }

    // The account name the basic-auth store saves must reach the KeePassXC adapter without any
    // “/”, or keepassxc-cli splits it into groups and the add fails.
    func testKeePassXCAddSendsTitleWithoutSlashes() throws {
        try installFakeAdapter(listedTitle: "unused")
        let dataSource = PasswordManagerDataSourceProvider.makeKeePassXCDataSource(browser: true,
                                                                                   adapterPath: adapterPath,
                                                                                   identifier: uniqueIdentifier)
        let name = basicAuthAccountName
        XCTAssertEqual(name, "http://localhost:8022 (QA22)")

        let (account, error) = add(dataSource, accountName: name)
        XCTAssertNil(error)
        XCTAssertNotNil(account)

        let request = try recordedRequest("add-account")
        let sent = try XCTUnwrap(request["accountName"] as? String)
        XCTAssertFalse(sent.contains("/"), "Sent \(sent)")
        XCTAssertEqual(sent, "http:\u{2215}\u{2215}localhost:8022 (QA22)")
        XCTAssertEqual(request["userName"] as? String, "qa")
        XCTAssertEqual(request["password"] as? String, "pw")

        // The account handed back to the caller keeps the name it asked for.
        XCTAssertEqual(account?.accountName, name)
    }

    // A title stored that way must list under the original name, so the basic-auth store's
    // lookup (which matches on accountName) finds the remembered credential.
    func testKeePassXCListMapsStoredTitleBackToAccountName() throws {
        try installFakeAdapter(listedTitle: "http:\u{2215}\u{2215}localhost:8022 (QA22)")
        let dataSource = PasswordManagerDataSourceProvider.makeKeePassXCDataSource(browser: true,
                                                                                   adapterPath: adapterPath,
                                                                                   identifier: uniqueIdentifier)
        let accounts = fetch(dataSource)
        XCTAssertEqual(accounts.map(\.accountName), [basicAuthAccountName])
        XCTAssertEqual(accounts.map(\.userName), ["qa"])
    }

    // Other adapters (Bitwarden, Keeper) accept “/” in account names, so what they store must
    // not change.
    func testOtherAdaptersReceiveAccountNameVerbatim() throws {
        try installFakeAdapter(listedTitle: "http://localhost:8022 (QA22)")
        let dataSource = AdapterPasswordDataSource(browser: true,
                                                   adapterPath: adapterPath,
                                                   identifier: uniqueIdentifier)
        let (_, error) = add(dataSource, accountName: basicAuthAccountName)
        XCTAssertNil(error)
        let request = try recordedRequest("add-account")
        XCTAssertEqual(request["accountName"] as? String, basicAuthAccountName)

        XCTAssertEqual(fetch(dataSource).map(\.accountName), [basicAuthAccountName])
    }

    func testKeePassXCTitleCodecRoundTrips() {
        let codec = AdapterAccountNameCodec.keePassXC
        for name in ["http://localhost:8022 (QA22)", "plain", "a/b/c", ""] {
            XCTAssertFalse(codec.encode(name).contains("/"))
            XCTAssertEqual(codec.decode(codec.encode(name)), name)
        }
    }
}
