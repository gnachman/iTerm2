import XCTest
@testable import iTerm2SharedARC

// The remembered answer for a site is keyed by these strings, so the prompt (which keys by
// the page's URL) and the settings panel (which keys by what the user typed) must agree.
final class iTermBrowserScriptingPermissionsTests: XCTestCase {
    private typealias Permissions = iTermBrowserScriptingPermissions

    func testJavaScriptOriginKeepsSchemeAndDropsPath() {
        XCTAssertEqual(Permissions.javaScriptOrigin(for: URL(string: "https://Example.COM/a/b?c#d")),
                       "https://example.com")
        XCTAssertEqual(Permissions.javaScriptOrigin(for: URL(string: "http://example.com/")),
                       "http://example.com")
    }

    func testJavaScriptOriginOmitsDefaultPortsOnly() {
        XCTAssertEqual(Permissions.javaScriptOrigin(for: URL(string: "https://example.com:443/")),
                       "https://example.com")
        XCTAssertEqual(Permissions.javaScriptOrigin(for: URL(string: "http://example.com:80/")),
                       "http://example.com")
        XCTAssertEqual(Permissions.javaScriptOrigin(for: URL(string: "http://127.0.0.1:8080/")),
                       "http://127.0.0.1:8080")
        XCTAssertEqual(Permissions.javaScriptOrigin(for: URL(string: "https://example.com:80/")),
                       "https://example.com:80")
    }

    // fetchAPIScriptingOrigin passes the page's location.origin through this, so it must
    // come back unchanged for the panel's typed input to match what the prompt stores.
    func testJavaScriptOriginRoundTripsLocationOrigin() {
        for origin in ["https://example.com",
                       "http://127.0.0.1:8080",
                       "http://[::1]:8080",
                       "https://xn--bcher-kva.example"] {
            XCTAssertEqual(Permissions.javaScriptOrigin(for: URL(string: origin)), origin)
        }
    }

    func testJavaScriptOriginRejectsPagesWithoutAWebOrigin() {
        XCTAssertNil(Permissions.javaScriptOrigin(for: nil))
        XCTAssertNil(Permissions.javaScriptOrigin(for: URL(string: "about:blank")))
        XCTAssertNil(Permissions.javaScriptOrigin(for: URL(string: "file:///etc/hosts")))
        XCTAssertNil(Permissions.javaScriptOrigin(for: URL(string: "iterm2-about:welcome")))
    }

    func testSiteFromInputAssumesHTTPS() {
        XCTAssertEqual(Permissions.site(from: "  Example.com  ", kind: .runJavaScript),
                       "https://example.com")
        XCTAssertEqual(Permissions.site(from: "example.com/page", kind: .loadURL),
                       "example.com")
    }

    func testSiteFromInputMatchesWhatThePromptStores() {
        let url = "http://localhost:3000/login"
        XCTAssertEqual(Permissions.site(from: url, kind: .runJavaScript),
                       Permissions.javaScriptOrigin(for: URL(string: url)))
        XCTAssertEqual(Permissions.site(from: url, kind: .loadURL), "localhost")
    }

    func testSiteFromInputRejectsNonsense() {
        XCTAssertNil(Permissions.site(from: "", kind: .runJavaScript))
        XCTAssertNil(Permissions.site(from: "   ", kind: .loadURL))
        XCTAssertNil(Permissions.site(from: "file:///tmp/x.html", kind: .runJavaScript))
    }

    func testIdentifiersIncludeTheSite() {
        XCTAssertEqual(Permissions.javaScriptIdentifier(origin: "https://example.com"),
                       "NoSyncBrowserJavaScriptAllowed_https://example.com")
        XCTAssertEqual(Permissions.loadURLIdentifier(host: "example.com"),
                       "NoSyncLoadURLAllowed_example.com")
    }
}

// These read and write the remembered answers in user defaults, using hosts no real
// prompt would produce, and remove them afterward.
@MainActor
final class iTermBrowserScriptingPermissionsStorageTests: XCTestCase {
    private typealias Permissions = iTermBrowserScriptingPermissions

    private let mixedCaseHost = "Example.ITerm2-Test"
    private var lowercaseHost: String { mixedCaseHost.lowercased() }

    override func setUp() {
        cleanUp()
    }

    override func tearDown() {
        cleanUp()
    }

    private func cleanUp() {
        let ud = iTermUserDefaults.userDefaults()
        for host in [mixedCaseHost, lowercaseHost] {
            let identifier = Permissions.loadURLIdentifier(host: host)
            iTermSuppressedAlerts.sharedInstance.unsuppressIdentifier(identifier)
            ud.removeObject(forKey: identifier)
            ud.removeObject(forKey: identifier + "_selection")
            ud.removeObject(forKey: identifier + "_SilenceUntil")
        }
    }

    private func savedSelection(host: String) -> Int? {
        return iTermWarning.conditionalSavedSelection(forIdentifier: Permissions.loadURLIdentifier(host: host))?.intValue
    }

    func testMixedCaseLoadURLAnswerMovesToLowercasedKey() {
        iTermWarning.setIdentifier(Permissions.loadURLIdentifier(host: mixedCaseHost),
                                   permanentSelection: .kiTermWarningSelection1)

        Permissions.migrateLoadURLAnswer(host: mixedCaseHost)

        XCTAssertEqual(savedSelection(host: lowercaseHost), 1)
        XCTAssertNil(savedSelection(host: mixedCaseHost))
    }

    func testMigrationKeepsAnAnswerAlreadySavedUnderTheLowercasedKey() {
        iTermWarning.setIdentifier(Permissions.loadURLIdentifier(host: mixedCaseHost),
                                   permanentSelection: .kiTermWarningSelection1)
        iTermWarning.setIdentifier(Permissions.loadURLIdentifier(host: lowercaseHost),
                                   permanentSelection: .kiTermWarningSelection0)

        Permissions.migrateLoadURLAnswer(host: mixedCaseHost)

        XCTAssertEqual(savedSelection(host: lowercaseHost), 0)
        XCTAssertNil(savedSelection(host: mixedCaseHost))
    }

    func testEntriesListMigratedAnswersOnly() {
        iTermWarning.setIdentifier(Permissions.loadURLIdentifier(host: mixedCaseHost),
                                   permanentSelection: .kiTermWarningSelection0)

        let entries = Permissions.entries().filter { $0.kind == .loadURL && $0.site.lowercased() == lowercaseHost }

        XCTAssertEqual(entries, [Permissions.Entry(kind: .loadURL, site: lowercaseHost, allowed: true)])
    }

    func testSavingDropsTheSuppressedAlertsRecord() {
        let identifier = Permissions.loadURLIdentifier(host: lowercaseHost)
        iTermWarning.setIdentifier(identifier, permanentSelection: .kiTermWarningSelection0)
        let registry = iTermSuppressedAlerts.sharedInstance
        registry.recordSuppression(withIdentifier: identifier,
                                   title: "Allow loading URLs?",
                                   heading: nil,
                                   selectionLabel: "OK")
        XCTAssertTrue(registry.currentlySuppressedAlerts().contains { $0.identifier == identifier })

        Permissions.save(Permissions.Entry(kind: .loadURL, site: lowercaseHost, allowed: false))

        XCTAssertFalse(registry.currentlySuppressedAlerts().contains { $0.identifier == identifier })
        XCTAssertEqual(savedSelection(host: lowercaseHost), 1)
    }
}
