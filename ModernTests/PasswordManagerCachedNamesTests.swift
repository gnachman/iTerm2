//
//  PasswordManagerCachedNamesTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

/// F-323: after a screen lock revoked password-manager authentication, the
/// trigger editor still listed saved account names from a class-level cache.
final class PasswordManagerCachedNamesTests: XCTestCase {
    private func setCachedNames(_ cls: AnyClass, _ names: [String]?) {
        _ = (cls as AnyObject).perform(NSSelectorFromString("setCachedCombinedAccountNames:"), with: names)
    }

    override func tearDown() {
        setCachedNames(iTermPasswordManagerWindowController.self, nil)
        setCachedNames(iTermBrowserPasswordManagerWindowController.self, nil)
        super.tearDown()
    }

    func testRevokingAuthenticationClearsTerminalCache() {
        setCachedNames(iTermPasswordManagerWindowController.self, ["secret user"])
        XCTAssertEqual(iTermPasswordManagerWindowController.cachedCombinedAccountNames(), ["secret user"])
        NotificationCenter.default.post(name: PasswordManagerDataSourceProvider.didRevokeAuthenticationNotification,
                                        object: PasswordManagerDataSourceProvider.forTerminal)
        XCTAssertNil(iTermPasswordManagerWindowController.cachedCombinedAccountNames())
    }

    func testRevokingBrowserAuthenticationLeavesTerminalCacheAlone() {
        setCachedNames(iTermPasswordManagerWindowController.self, ["a"])
        setCachedNames(iTermBrowserPasswordManagerWindowController.self, ["b"])
        NotificationCenter.default.post(name: PasswordManagerDataSourceProvider.didRevokeAuthenticationNotification,
                                        object: PasswordManagerDataSourceProvider.forBrowser)
        XCTAssertEqual(iTermPasswordManagerWindowController.cachedCombinedAccountNames(), ["a"])
        XCTAssertNil(iTermBrowserPasswordManagerWindowController.cachedCombinedAccountNames())
    }
}
