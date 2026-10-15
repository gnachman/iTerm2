import XCTest
@testable import iTerm2SharedARC

// The stoplight hotbox in a compact window collapses to a chevron when a
// clickable decoration lies beneath it. A browser session's navigation bar
// (back, forward, reload) is such a decoration, so a hotbox over it must not
// be revealed or the buttons become unreachable.
// A real iTermBrowserViewController needs WebKit, a profile model and the
// history database, so these tests stand in for its toolbar by overriding
// SessionView.browserClickableDecorationViews.
final class SessionViewClickableDecorationTests: XCTestCase {
    private final class BrowserLikeSessionView: SessionView {
        var browserDecorations: [NSView] = []
        override var browserClickableDecorationViews: [NSView] {
            return browserDecorations
        }
    }

    private let windowSize = NSSize(width: 640, height: 480)
    private var window: NSWindow!

    override func setUp() {
        super.setUp()
        window = NSWindow(contentRect: NSRect(origin: .zero, size: windowSize),
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: true)
        window.isReleasedWhenClosed = false
    }

    override func tearDown() {
        window.contentView = nil
        window = nil
        super.tearDown()
    }

    // Roughly where the stoplight hotbox sits: the window's top-left corner.
    private var hotboxRect: NSRect {
        return NSRect(x: 0, y: windowSize.height - 30, width: 70, height: 30)
    }

    // Installs a session view filling the window with a 44pt navigation bar
    // along its top edge, like a browser session's toolbar.
    private func makeBrowserSessionView() -> (BrowserLikeSessionView, NSView) {
        let sessionView = BrowserLikeSessionView(frame: NSRect(origin: .zero, size: windowSize))
        window.contentView = sessionView
        let navBar = NSView(frame: NSRect(x: 0,
                                          y: windowSize.height - 44,
                                          width: windowSize.width,
                                          height: 44))
        sessionView.addSubview(belowFind: navBar)
        sessionView.browserDecorations = [navBar]
        return (sessionView, navBar)
    }

    func testNonBrowserSessionHasNoBrowserDecorations() {
        let sessionView = SessionView(frame: NSRect(origin: .zero, size: windowSize))
        window.contentView = sessionView
        XCTAssertEqual(sessionView.browserClickableDecorationViews.count, 0)
        XCTAssertFalse(sessionView.clickableDecorationIntersectsWindowRect(hotboxRect))
    }

    func testBrowserNavigationBarUnderHotboxCountsAsClickable() {
        let (sessionView, _) = makeBrowserSessionView()
        XCTAssertTrue(sessionView.clickableDecorationIntersectsWindowRect(hotboxRect))
    }

    func testHiddenBrowserNavigationBarIsNotClickable() {
        let (sessionView, navBar) = makeBrowserSessionView()
        navBar.isHidden = true
        XCTAssertFalse(sessionView.clickableDecorationIntersectsWindowRect(hotboxRect))
    }

    func testBrowserNavigationBarAwayFromHotboxDoesNotCount() {
        let (sessionView, _) = makeBrowserSessionView()
        let bottomLeft = NSRect(x: 0, y: 0, width: 70, height: 30)
        XCTAssertFalse(sessionView.clickableDecorationIntersectsWindowRect(bottomLeft))
    }
}
