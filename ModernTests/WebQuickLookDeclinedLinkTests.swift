//
//  WebQuickLookDeclinedLinkTests.swift
//  ModernTests
//
//  When the pointer rests on a web link that the hover allowlist refuses, the session shows an
//  announcement offering to add the link’s domain. It is offered once per domain per view, never
//  after “Don’t Ask Again”, and its button saves the domain.
//

import XCTest
@testable import iTerm2SharedARC

// A stand-in for the text view. Also used by WebQuickLookCoordinatorWindowTests.
final class FakeWebQuickLookHost: NSObject, iTermWebQuickLookHost {
    var queued = [(announcement: iTermAnnouncementViewController, identifier: String)]()

    func webQuickLookCoord(for point: NSPoint, allowRightMarginOverflow: Bool) -> VT100GridCoord {
        return VT100GridCoordMake(0, 0)
    }
    func webQuickLookTotalScrollbackOverflow() -> Int64 { 0 }
    func webQuickLookShowingAlternateScreen() -> Bool { false }
    func webQuickLookGridWidth() -> Int32 { 80 }
    func webQuickLookCellSize() -> NSSize { NSSize(width: 10, height: 16) }
    func webQuickLookVerticalOffset() -> CGFloat { 0 }
    func webQuickLookURLActionHelper() -> iTermURLActionHelper {
        return iTermURLActionHelper(semanticHistoryController: iTermSemanticHistoryController())
    }
    func webQuickLookURL(for action: URLAction) -> URL? { nil }
    func webQuickLookUnderlinedRange() -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRange() }
    func webQuickLookSetUnderlinedRange(_ range: VT100GridAbsWindowedRange) {}
    func webQuickLookRemoveUnderline() -> Bool { false }
    func webQuickLookShowHoverURL(_ url: String?, anchor: VT100GridWindowedRange) {}
    func webQuickLookUpdateTrackingAreas() {}
    func webQuickLookQueue(_ announcement: iTermAnnouncementViewController, identifier: String) {
        queued.append((announcement, identifier))
    }
}

final class WebQuickLookDeclinedLinkTests: XCTestCase {
    private var host: FakeWebQuickLookHost!
    private var view: NSView!
    private var coordinator: iTermWebQuickLookCoordinator!
    private var savedAllowlist: Any?
    private var savedNeverOffer: Any?

    override func setUp() {
        super.setUp()
        // The stored values, not iTermPreferences, which fills in defaults, so tearDown can remove
        // a key that was unset.
        savedAllowlist = iTermUserDefaults.userDefaults().object(forKey: kPreferenceKeyQuickLookHoverDomainAllowlist)
        savedNeverOffer = iTermUserDefaults.userDefaults().object(forKey: iTermWebQuickLookCoordinator.neverOfferToAllowDomainKey)
        iTermUserDefaults.userDefaults().removeObject(forKey: iTermWebQuickLookCoordinator.neverOfferToAllowDomainKey)
        iTermPreferences.setObject(["linear.app"], forKey: kPreferenceKeyQuickLookHoverDomainAllowlist)
        host = FakeWebQuickLookHost()
        view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        coordinator = iTermWebQuickLookCoordinator(view: view, host: host)
    }

    override func tearDown() {
        coordinator.tearDown()
        coordinator = nil
        view = nil
        host = nil
        iTermPreferences.setObject(savedAllowlist, forKey: kPreferenceKeyQuickLookHoverDomainAllowlist)
        iTermUserDefaults.userDefaults().set(savedNeverOffer, forKey: iTermWebQuickLookCoordinator.neverOfferToAllowDomainKey)
        super.tearDown()
    }

    private func decline(_ string: String) {
        coordinator.hoverControllerDeclinedLink(url: URL(string: string)!)
    }

    func testOffersOncePerDomain() {
        decline("https://www.example.com/a")
        XCTAssertEqual(host.queued.count, 1)
        XCTAssertEqual(host.queued.first?.identifier, iTermWebQuickLookCoordinator.announcementIdentifier)

        decline("https://example.com/b")
        XCTAssertEqual(host.queued.count, 1, "www. and the bare domain are one offer")

        decline("https://example.org/")
        XCTAssertEqual(host.queued.count, 2, "another domain gets its own offer")
    }

    func testAllowButtonSavesTheDomain() {
        decline("https://www.example.com/a")
        host.queued.first?.announcement.completion?(0)
        XCTAssertEqual(iTermQuickLookDomainAllowlist.savedDomains(), ["example.com", "linear.app"])
        XCTAssertTrue(iTermQuickLookDomainAllowlist.fromSettings().allows(URL(string: "https://www.example.com/a")!))
    }

    func testDontAskAgainStopsOffers() {
        decline("https://example.com/")
        host.queued.first?.announcement.completion?(1)
        XCTAssertEqual(iTermQuickLookDomainAllowlist.savedDomains(), ["linear.app"])

        decline("https://example.org/")
        XCTAssertEqual(host.queued.count, 1)

        let other = iTermWebQuickLookCoordinator(view: view, host: host)
        other.hoverControllerDeclinedLink(url: URL(string: "https://example.net/")!)
        other.tearDown()
        XCTAssertEqual(host.queued.count, 1, "in every view")
    }

    func testDismissingSavesNothing() {
        decline("https://example.com/")
        host.queued.first?.announcement.completion?(-2)
        XCTAssertEqual(iTermQuickLookDomainAllowlist.savedDomains(), ["linear.app"])
    }

    func testNonWebURLsAreNotOffered() {
        decline("file:///tmp/x")
        decline("mailto:a@example.com")
        XCTAssertTrue(host.queued.isEmpty)
    }
}
