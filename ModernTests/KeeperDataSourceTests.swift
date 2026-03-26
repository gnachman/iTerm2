//
//  KeeperDataSourceTests.swift
//  iTerm2
//
//  Unit tests for Keeper keychain/URL storage, settings-sheet / API key dialog wiring,
//  and pwmplugin JSON protocol smoke checks against the bundled iterm2-keeper-adapter.
//  Commander HTTP and response parsing are covered by pwmplugin; run `swift test` in pwmplugin/.
//

import XCTest
import AppKit
@testable import iTerm2SharedARC

final class KeeperDataSourceTests: XCTestCase {

    private typealias HandshakeRequest = PasswordManagerProtocol.HandshakeRequest
    private typealias HandshakeResponse = PasswordManagerProtocol.HandshakeResponse
    private typealias ErrorResponse = PasswordManagerProtocol.ErrorResponse

    private var bundledKeeperAdapterPath: String? {
        Bundle(for: AdapterPasswordDataSource.self).path(forAuxiliaryExecutable: "iterm2-keeper-adapter")
    }

    private func runKeeperAdapter(subcommand: String, input: Data, timeout: TimeInterval = 10,
                                  file: StaticString = #file, line: UInt = #line,
                                  completion: @escaping (Output?, Error?) -> Void) {
        guard let path = bundledKeeperAdapterPath else {
            XCTFail("Missing iterm2-keeper-adapter in test bundle", file: file, line: line)
            completion(nil, nil)
            return
        }
        let request = CommandLinePasswordDataSource.CommandRequestWithInput(
            command: path,
            args: [subcommand],
            env: [:],
            input: input)
        let exp = expectation(description: "keeper adapter \(subcommand)")
        request.execAsync { output, error in
            completion(output, error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: timeout)
    }

    override func setUp() {
        super.setUp()
        clearOverrides()
        KeeperDataSource.showKeeperSettingsSheetHandler = nil
    }

    override func tearDown() {
        clearOverrides()
        KeeperDataSource.showKeeperSettingsSheetHandler = nil
        super.tearDown()
    }

    private func clearOverrides() {
        KeeperTestOverrides.apiKeyFromKeychain = nil
        KeeperTestOverrides.secureKeychainReturns = nil
        KeeperTestOverrides.standardKeychainReturns = nil
        KeeperTestOverrides.storeAPIKeyInKeychain = nil
        KeeperTestOverrides.deleteAPIKeyFromKeychain = nil
        KeeperTestOverrides.showAPIKeyDialogOverride = nil
        KeeperTestOverrides.showAPIKeyDialogUIOverride = nil
        KeeperTestOverrides.callDialogUI = nil
        KeeperTestOverrides.defaultDialogUI = nil
        KeeperTestOverrides.fallbackDialogUIForCoverage = nil
        KeeperTestOverrides.apiURLFromStorage = nil
        KeeperTestOverrides.forceAccessControlCreationToFail = false
        KeeperTestOverrides.forceSecItemAddToFail = false
    }

    func testSetShowKeeperSettingsSheetHandler_matchesStaticProperty() {
        var called = false
        KeeperDataSource.setShowKeeperSettingsSheetHandler { _, completion in
            called = true
            completion(nil)
        }
        XCTAssertNotNil(KeeperDataSource.showKeeperSettingsSheetHandler)
        KeeperDataSource.showKeeperSettingsSheetHandler?(nil) { _ in }
        XCTAssertTrue(called)
        KeeperDataSource.setShowKeeperSettingsSheetHandler(nil)
        XCTAssertNil(KeeperDataSource.showKeeperSettingsSheetHandler)
    }

    func testKeeperResolvedDialogFunction_callingReturnedFunction_completesWithCancel() {
        KeeperTestOverrides.callDialogUI = nil
        KeeperTestOverrides.defaultDialogUI = nil
        KeeperTestOverrides.fallbackDialogUIForCoverage = nil
        let fn = keeperResolvedDialogFunction()
        let exp = expectation(description: "dialog")
        fn(nil, nil) { result in
            if case .cancel? = result { } else { XCTFail("expected .cancel, got \(String(describing: result))") }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
    }

    func testKeeperShowAPIKeyDialog_noSheetHandler_completesWithCancel() {
        KeeperDataSource.showKeeperSettingsSheetHandler = nil
        KeeperTestOverrides.showAPIKeyDialogOverride = nil
        KeeperTestOverrides.showAPIKeyDialogUIOverride = nil
        var result: KeeperAPIKeyPromptResult?
        keeperShowAPIKeyDialog(existingKey: nil, window: nil) { result = $0 }
        if case .cancel? = result { } else { XCTFail("expected .cancel when no sheet handler, got \(String(describing: result))") }
    }

    func testKeeperShowAPIKeyDialog_settingsSheetHandler_useNew() {
        var handlerCalled = false
        KeeperDataSource.showKeeperSettingsSheetHandler = { _, completion in
            handlerCalled = true
            completion("key-from-sheet")
        }
        defer { KeeperDataSource.showKeeperSettingsSheetHandler = nil }
        var result: KeeperAPIKeyPromptResult?
        keeperShowAPIKeyDialog(existingKey: nil, window: nil) { result = $0 }
        XCTAssertTrue(handlerCalled)
        if case .useNew(let k)? = result, k == "key-from-sheet" { } else { XCTFail("expected .useNew, got \(String(describing: result))") }
    }

    func testKeeperShowAPIKeyDialog_settingsSheetHandler_emptyKey_isCancel() {
        KeeperDataSource.showKeeperSettingsSheetHandler = { _, completion in
            completion("")
        }
        defer { KeeperDataSource.showKeeperSettingsSheetHandler = nil }
        var result: KeeperAPIKeyPromptResult?
        keeperShowAPIKeyDialog(existingKey: nil, window: nil) { result = $0 }
        if case .cancel? = result { } else { XCTFail("expected .cancel") }
    }

    func testKeeperMigrateLegacyKeeperTokenIfNeeded_userDefaultsPath() {
        iTermUserDefaults.userDefaults().set("legacy-key-from-ud", forKey: keeperLegacyUserDefaultsAPIKeyKey)
        iTermUserDefaults.userDefaults().set("https://legacy-url.test", forKey: keeperLegacyUserDefaultsAPIURLKey)
        defer {
            iTermUserDefaults.userDefaults().removeObject(forKey: keeperLegacyUserDefaultsAPIKeyKey)
            iTermUserDefaults.userDefaults().removeObject(forKey: keeperLegacyUserDefaultsAPIURLKey)
        }
        var storedKey: String?
        KeeperTestOverrides.storeAPIKeyInKeychain = { key in storedKey = key }
        defer { KeeperTestOverrides.storeAPIKeyInKeychain = nil }
        keeperMigrateLegacyKeeperTokenIfNeeded()
        XCTAssertEqual(storedKey, "legacy-key-from-ud")
        XCTAssertNil(iTermUserDefaults.userDefaults().string(forKey: keeperLegacyUserDefaultsAPIKeyKey))
        XCTAssertEqual(iTermUserDefaults.userDefaults().string(forKey: keeperLegacyUserDefaultsAPIURLKey), "https://legacy-url.test")
    }

    func testKeeperAPIURLFromStorage_withNoOverride_readsUserDefaults() {
        let url = "https://from-userdefaults.test"
        iTermUserDefaults.userDefaults().set(url, forKey: keeperLegacyUserDefaultsAPIURLKey)
        defer { iTermUserDefaults.userDefaults().removeObject(forKey: keeperLegacyUserDefaultsAPIURLKey) }
        XCTAssertEqual(keeperAPIURLFromStorage(), url)
    }

    func testKeeperStoreAPIURLInKeychain_storesInUserDefaults() {
        let url = "https://store-test.test"
        keeperStoreAPIURLInKeychain(url)
        defer { keeperClearAPIURLStorage() }
        XCTAssertEqual(iTermUserDefaults.userDefaults().string(forKey: keeperLegacyUserDefaultsAPIURLKey), url)
    }

    func testKeeperStoreAPIURLInKeychain_whitespaceOnly_setsNilInUserDefaults() {
        iTermUserDefaults.userDefaults().set("https://to-clear.test", forKey: keeperLegacyUserDefaultsAPIURLKey)
        keeperStoreAPIURLInKeychain("   ")
        XCTAssertNil(iTermUserDefaults.userDefaults().string(forKey: keeperLegacyUserDefaultsAPIURLKey))
        keeperClearAPIURLStorage()
    }

    func testKeeperClearAPIURLStorage_removesFromUserDefaults() {
        iTermUserDefaults.userDefaults().set("https://to-clear.test", forKey: keeperLegacyUserDefaultsAPIURLKey)
        keeperClearAPIURLStorage()
        XCTAssertNil(iTermUserDefaults.userDefaults().string(forKey: keeperLegacyUserDefaultsAPIURLKey))
    }

    func testKeeperAPIKeyFromKeychain_standardKeychainOnly_migratesAndReturnsKey() {
        KeeperTestOverrides.secureKeychainReturns = { nil }
        KeeperTestOverrides.standardKeychainReturns = { "migrate-key" }
        var stored: String?
        KeeperTestOverrides.storeAPIKeyInKeychain = { stored = $0 }
        defer {
            KeeperTestOverrides.secureKeychainReturns = nil
            KeeperTestOverrides.standardKeychainReturns = nil
            KeeperTestOverrides.storeAPIKeyInKeychain = nil
        }
        let key = keeperAPIKeyFromKeychain()
        XCTAssertEqual(key, "migrate-key")
        XCTAssertEqual(stored, "migrate-key")
    }

    func testKeeperStoreAPIKeyInStandardKeychain_doesNotCrash() {
        keeperStoreAPIKeyInStandardKeychain("standard-keychain-test-key")
    }

    func testSetKeeperSettingsAPIKey_nonEmpty_usesGlobalStoreOverride() {
        guard let adapterPath = Bundle(for: AdapterPasswordDataSource.self).path(forAuxiliaryExecutable: "iterm2-keeper-adapter") else {
            XCTFail("Missing iterm2-keeper-adapter in test bundle")
            return
        }
        var storedKey: String?
        KeeperTestOverrides.storeAPIKeyInKeychain = { storedKey = $0 }
        defer { KeeperTestOverrides.storeAPIKeyInKeychain = nil }
        let ds = AdapterPasswordDataSource(browser: false, adapterPath: adapterPath, identifier: "Keeper Security")
        ds.setKeeperSettingsAPIKey("stored-via-global-override")
        XCTAssertEqual(storedKey, "stored-via-global-override")
    }

    func testSetKeeperSettingsAPIKey_forceAccessControlFail_stillStoresViaFallback() {
        guard let adapterPath = Bundle(for: AdapterPasswordDataSource.self).path(forAuxiliaryExecutable: "iterm2-keeper-adapter") else {
            XCTFail("Missing iterm2-keeper-adapter in test bundle")
            return
        }
        KeeperTestOverrides.forceAccessControlCreationToFail = true
        defer { KeeperTestOverrides.forceAccessControlCreationToFail = false }
        let ds = AdapterPasswordDataSource(browser: false, adapterPath: adapterPath, identifier: "Keeper Security")
        ds.setKeeperSettingsAPIKey("key-via-access-control-fail")
        XCTAssertEqual(ds.keeperSettingsAPIKey(), "key-via-access-control-fail")
    }

    func testSetKeeperSettingsAPIKey_forceSecItemAddFail_stillStoresViaFallback() {
        guard let adapterPath = Bundle(for: AdapterPasswordDataSource.self).path(forAuxiliaryExecutable: "iterm2-keeper-adapter") else {
            XCTFail("Missing iterm2-keeper-adapter in test bundle")
            return
        }
        KeeperTestOverrides.forceSecItemAddToFail = true
        defer { KeeperTestOverrides.forceSecItemAddToFail = false }
        let ds = AdapterPasswordDataSource(browser: false, adapterPath: adapterPath, identifier: "Keeper Security")
        ds.setKeeperSettingsAPIKey("key-via-secitem-fail")
        XCTAssertEqual(ds.keeperSettingsAPIKey(), "key-via-secitem-fail")
    }

    // MARK: - Bundled adapter (pwmplugin JSON protocol)

    func testBundledKeeperAdapter_handshake_returnsExpectedHandshakeResponse() {
        guard bundledKeeperAdapterPath != nil else {
            XCTFail("Missing iterm2-keeper-adapter in test bundle")
            return
        }
        let req = HandshakeRequest(iTermVersion: "ModernTests", minProtocolVersion: 0, maxProtocolVersion: 0)
        let data = try! JSONEncoder().encode(req)
        runKeeperAdapter(subcommand: "handshake", input: data) { output, error in
            XCTAssertNil(error)
            guard let output else {
                XCTFail("no output")
                return
            }
            XCTAssertEqual(output.returnCode, 0)
            let decoded = try? JSONDecoder().decode(HandshakeResponse.self, from: output.stdout)
            XCTAssertNotNil(decoded)
            XCTAssertEqual(decoded?.protocolVersion, 0)
            XCTAssertEqual(decoded?.name, "Keeper Security")
            XCTAssertTrue(decoded?.requiresMasterPassword ?? false)
            XCTAssertTrue(decoded?.canSetPasswords ?? false)
            XCTAssertTrue(decoded?.needsPathToDatabase ?? false)
            XCTAssertNil(decoded?.userAccounts)
        }
    }

    func testBundledKeeperAdapter_handshake_invalidJson_returnsErrorResponse() {
        guard bundledKeeperAdapterPath != nil else {
            XCTFail("Missing iterm2-keeper-adapter in test bundle")
            return
        }
        runKeeperAdapter(subcommand: "handshake", input: Data("{not-json".utf8)) { output, error in
            XCTAssertNil(error)
            guard let output else {
                XCTFail("no output")
                return
            }
            XCTAssertNotEqual(output.returnCode, 0)
            let err = try? JSONDecoder().decode(ErrorResponse.self, from: output.stdout)
            XCTAssertNotNil(err)
            XCTAssertFalse(err?.error.isEmpty ?? true)
        }
    }

    func testBundledKeeperAdapter_handshake_negativeMaxProtocolVersion_rejected() {
        guard bundledKeeperAdapterPath != nil else {
            XCTFail("Missing iterm2-keeper-adapter in test bundle")
            return
        }
        let req = HandshakeRequest(iTermVersion: "ModernTests", minProtocolVersion: 0, maxProtocolVersion: -1)
        let data = try! JSONEncoder().encode(req)
        runKeeperAdapter(subcommand: "handshake", input: data) { output, error in
            XCTAssertNil(error)
            guard let output else {
                XCTFail("no output")
                return
            }
            XCTAssertNotEqual(output.returnCode, 0)
            let err = try? JSONDecoder().decode(ErrorResponse.self, from: output.stdout)
            XCTAssertEqual(err?.error, "Protocol version 0 is required")
        }
    }

    func testAdapterPasswordDataSource_checkAvailability_trueForBundledKeeperAdapter() {
        guard let adapterPath = bundledKeeperAdapterPath else {
            XCTFail("Missing iterm2-keeper-adapter in test bundle")
            return
        }
        let ds = AdapterPasswordDataSource(browser: false, adapterPath: adapterPath, identifier: "Keeper Security")
        XCTAssertTrue(ds.checkAvailability())
    }
}
