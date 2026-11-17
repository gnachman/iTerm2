//
//  iTermWebQuickLookCoordinator.swift
//  iTerm2SharedARC
//
//  Owns a text view's web Quick Look: the popover (opened by force press, the context menu or
//  hovering a link), the hover state machine, and the hover cue (the underline and URL bar shown
//  while a hover preview is pending). The text view forwards events and asks a few questions of
//  it; everything it needs from the text view goes through iTermWebQuickLookHost.
//

import AppKit
import WebKit

// What the coordinator needs from the text view it serves. Points are in the view's coordinates.
@objc(iTermWebQuickLookHost)
protocol iTermWebQuickLookHost: AnyObject {
    @objc(webQuickLookCoordForPoint:allowRightMarginOverflow:)
    func webQuickLookCoord(for point: NSPoint, allowRightMarginOverflow: Bool) -> VT100GridCoord

    // Lines dropped off the top of the scrollback so far.
    func webQuickLookTotalScrollbackOverflow() -> Int64
    func webQuickLookShowingAlternateScreen() -> Bool
    // Columns in the grid.
    func webQuickLookGridWidth() -> Int32
    func webQuickLookCellSize() -> NSSize
    // How far line 0 of the visual grid is from y=0 in the view, the inverse of the correction
    // coordForPoint makes.
    func webQuickLookVerticalOffset() -> CGFloat

    func webQuickLookURLActionHelper() -> iTermURLActionHelper
    // The URL Quick Look would show for an action, or nil when it would show none.
    @objc(webQuickLookURLForAction:)
    func webQuickLookURL(for action: URLAction) -> URL?

    func webQuickLookUnderlinedRange() -> VT100GridAbsWindowedRange
    // Sets the underlined range and redraws.
    func webQuickLookSetUnderlinedRange(_ range: VT100GridAbsWindowedRange)
    // Removes the underline. Returns whether there was one.
    func webQuickLookRemoveUnderline() -> Bool

    // Shows the URL bar for url anchored to a range, or hides it when url is nil.
    @objc(webQuickLookShowHoverURL:anchor:)
    func webQuickLookShowHoverURL(_ url: String?, anchor: VT100GridWindowedRange)
    // Whether mouse-moved events are wanted changed.
    func webQuickLookUpdateTrackingAreas()
    // Shows an announcement in the session, replacing any with the same identifier.
    @objc(webQuickLookQueueAnnouncement:identifier:)
    func webQuickLookQueue(_ announcement: iTermAnnouncementViewController, identifier: String)
}

@objc(iTermWebQuickLookCoordinator)
final class iTermWebQuickLookCoordinator: NSObject, NSPopoverDelegate, iTermQuickLookHoverControllerDelegate {
    private weak var view: NSView?
    private weak var host: iTermWebQuickLookHost?

    // The web Quick Look popover this view showed last, while it is open.
    var popover: NSPopover?
    // Whether popover was opened by hovering a link (as opposed to force press or a menu).
    var popoverOpenedByHover = false

    // Drives Quick Look on hover. Created on first use while hovering is turned on.
    var controller: iTermQuickLookHoverController?
    // The hover mode the controller was last configured with.
    private var mode = iTermQuickLookHoverMode.off

    // The link the hover controller resolved last, kept so its cue can be shown without resolving
    // again.
    private var resolvedURL: URL?
    // Absolute, like the underlined range, so it stays right as lines scroll off the top between
    // resolving and showing the cue or opening.
    private var resolvedAbsVisualRange = VT100GridAbsWindowedRange()
    private var resolvedUnderlinedRange = VT100GridAbsWindowedRange()

    // The hover cue (underline and URL bar) shown in Hover mode before a preview opens. Nil means
    // no cue.
    var cueURL: String?
    // Absolute, so the URL bar's anchor follows the link as lines scroll off the top.
    private var cueAbsVisualRange = VT100GridAbsWindowedRange()
    var cueUnderlinedRange = VT100GridAbsWindowedRange()

    // The URL and absolute visual range of the hover-opened preview's link, so its rects can follow
    // it as the content moves.
    private var previewLinkURL: URL?
    private var previewLinkAbsVisualRange = VT100GridAbsWindowedRange()

    // Where the URL bar was last put for the cue, so refreshes that didn't move the link don't lay
    // it out again.
    private var lastShownCueAnchor: VT100GridWindowedRange?

    // The full resolution in flight, cancelled when another starts.
    private var pendingResolution: iTermCancelable?
    // Bumped when a resolution is cancelled or superseded. Cancelling doesn't stop every stage of a
    // resolution, so an answer for an older number is ignored.
    private var resolutionGeneration = 0

    // Whether the alternate screen showed at the last refresh, to notice a switch that scrolled
    // nothing.
    private var lastShowedAlternateScreen = false

    // Replaces the pointer location read from the window. Tests have no window.
    var pointerLocationForTesting: NSPoint?

    // Domains this view already offered to add to the allowlist, so resting on their links again
    // doesn't offer again.
    private(set) var offeredDomains = Set<String>()
    static let announcementIdentifier = "QuickLookHoverAllowDomain"  // Localization unneeded
    // Set by “Don’t Ask Again” on the offer to add a domain.
    static let neverOfferToAllowDomainKey = "NoSyncQuickLookHoverNeverOfferToAllowDomain"  // Localization unneeded

    // Long enough that sweeping the pointer across text doesn't flash cues, short enough that the
    // cue shows well before a preview opens at the default delay.
    private static let cueSettleDelay: TimeInterval = 0.1

    @objc(initWithView:host:)
    init(view: NSView, host: iTermWebQuickLookHost) {
        self.view = view
        self.host = host
        super.init()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(windowDidResignKey(_:)),
                                               name: NSWindow.didResignKeyNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(windowDidBecomeKey(_:)),
                                               name: NSWindow.didBecomeKeyNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(secureUserDefaultDidChange(_:)),
                                               name: iTermSecureUserDefaults.didChange,
                                               object: nil)
        iTermPreferenceDidChangeNotification.subscribe(self) { [weak self] notification in
            if Self.preferenceKeys.contains(notification.key) {
                self?.preferencesDidChange()
            }
        }
    }

    // Closes the popover without telling the view, which is going away.
    @objc func tearDown() {
        cancelPendingResolution()
        if let popover {
            popover.delegate = nil
            popover.close()
            Self.tearDownContent(of: popover)
            self.popover = nil
        }
    }

    // MARK: - Preferences

    static var preferenceKeys: Set<String> {
        return [kPreferenceKeyQuickLookHoverMode,
                kPreferenceKeyQuickLookHoverDelay,
                kPreferenceKeyQuickLookHoverAutoCloseDelay,
                kPreferenceKeyQuickLookHoverDomainAllowlist,
                kPreferenceKeyQuickLookHoverIncludesPlainTextURLs]
    }

    static var currentMode: iTermQuickLookHoverMode {
        return iTermQuickLookHoverMode(rawValue: Int(iTermPreferences.int(forKey: kPreferenceKeyQuickLookHoverMode))) ?? .off
    }

    // Hover previews only OSC 8 hyperlinks unless the user also wants plain-text URLs found by URL
    // detection, which often grab neighboring text (such as escape sequences in a command line).
    // Force press and the context menu are not gated by this.
    static func shouldHoverPreview(isOSC8: Bool, includesPlainTextURLs: Bool) -> Bool {
        return isOSC8 || includesPlainTextURLs
    }

    static var includesPlainTextURLs: Bool {
        return iTermPreferences.bool(forKey: kPreferenceKeyQuickLookHoverIncludesPlainTextURLs)
    }

    private func reloadPreferences() {
        mode = Self.currentMode
        controller?.configure(mode: mode,
                              delay: iTermPreferences.double(forKey: kPreferenceKeyQuickLookHoverDelay),
                              autoCloseDelay: iTermPreferences.double(forKey: kPreferenceKeyQuickLookHoverAutoCloseDelay),
                              allowlist: iTermQuickLookDomainAllowlist.fromSettings())
    }

    private func preferencesDidChange() {
        if controller != nil {
            reloadPreferences()
        }
        // Plain hover mode needs mouse-moved events, which depend on the tracking areas.
        host?.webQuickLookUpdateTrackingAreas()
    }

    @objc private func secureUserDefaultDidChange(_ notification: Notification) {
        // The allow-all-domains setting is part of the allowlist.
        if controller != nil {
            reloadPreferences()
        }
    }

    private func controllerCreatingIfNeeded() -> iTermQuickLookHoverController? {
        if let controller {
            return controller
        }
        if Self.currentMode == .off {
            return nil
        }
        DLog("Create Quick Look hover controller for \(String(describing: view))")
        let controller = iTermQuickLookHoverController(scheduler: iTermQuickLookTimerScheduler())
        controller.cueSettleDelay = Self.cueSettleDelay
        controller.delegate = self
        self.controller = controller
        reloadPreferences()
        return controller
    }

    // MARK: - Showing and closing the popover

    // Shows a web page in a Quick Look popover, replacing any this view already shows. The engine
    // (legacy or the built-in browser's) follows iTermQuickLookEngineSelector.
    @objc(showURL:atPointInWindow:openedByHover:)
    func show(url: URL, atPointInWindow pointInWindow: NSPoint, openedByHover: Bool) {
        DLog("Show web Quick Look for \(url) openedByHover=\(openedByHover)")
        let replacesHoverPreview = !openedByHover && popover != nil && popoverOpenedByHover
        close()
        if replacesHoverPreview {
            // The hover controller didn't ask for this, so tell it its preview is gone.
            controller?.previewClosed()
        }
        let newPopover: NSPopover?
        if openedByHover {
            // Whatever the engine setting, a hover preview gets the browser preview's protections:
            // a throwaway cookie store, no dialogs or pop-ups until clicked, and navigation limited
            // to the allowlist. It never needs the plugin, since it doesn't share the login store.
            newPopover = showBrowserPopover(atPointInWindow: pointInWindow,
                                            url: url,
                                            hoverAllowlist: iTermQuickLookDomainAllowlist.fromSettings())
        } else {
            switch iTermQuickLookEngineSelector.currentEngine() {
            case .legacy:
                newPopover = showLegacyPopover(atPointInWindow: pointInWindow, url: url)
            case .browser:
                newPopover = showBrowserPopover(atPointInWindow: pointInWindow, url: url, hoverAllowlist: nil)
            @unknown default:
                newPopover = nil
            }
        }
        setPopover(newPopover, openedByHover: openedByHover)
        if openedByHover, let newPopover {
            prepareHoverOpened(newPopover)
        }
    }

    // Closes the popover, if any.
    @objc func close() {
        guard let popover else {
            return
        }
        DLog("Close web Quick Look \(popover)")
        // Forget it first so that popoverDidClose knows this closed it.
        setPopover(nil, openedByHover: false)
        popover.close()
        // A programmatic close does not promise popoverDidClose, so tear down here too.
        Self.tearDownContent(of: popover)
    }

    private func setPopover(_ newPopover: NSPopover?, openedByHover: Bool) {
        let hadHoverPreview = hasHoverOpenedPreview
        popover = newPopover
        popoverOpenedByHover = newPopover != nil && openedByHover
        if !popoverOpenedByHover {
            previewLinkURL = nil
        }
        if hadHoverPreview != hasHoverOpenedPreview {
            // wantsMouseMovementEvents depends on this, and mouse-moved events depend on the
            // tracking areas.
            host?.webQuickLookUpdateTrackingAreas()
        }
    }

    var hasHoverOpenedPreview: Bool {
        return popover != nil && popoverOpenedByHover
    }

    // Whether a preview the user opened deliberately (force press or the context menu) is open.
    // Hover must not replace it.
    private var hasDeliberatelyOpenedPreview: Bool {
        return popover != nil && !popoverOpenedByHover
    }

    // Stops the page in a popover and closes its sign-in popups. Safe to call more than once.
    private static func tearDownContent(of popover: NSPopover) {
        switch popover.contentViewController {
        case let viewController as iTermWebViewWrapperViewController:
            viewController.terminateWebView()
        case let viewController as iTermBrowserQuickLookViewController:
            viewController.tearDown()
        default:
            break
        }
    }

    // A preview opened by hovering must not take keyboard focus from the terminal, and the hover
    // controller needs to know when the user clicks or types into it.
    private func prepareHoverOpened(_ popover: NSPopover) {
        if let viewController = popover.contentViewController as? iTermBrowserQuickLookViewController {
            viewController.onUserInteraction = { [weak self] in
                self?.controller?.previewClicked()
            }
        }
        if NSApp.isActive, let window = view?.window, !window.isKeyWindow {
            DLog("Hover-opened Quick Look took key; giving it back to \(window)")
            window.makeKey()
        }
        // Showing the popover can take key from this window before the popover is recorded as
        // hover opened, and PseudoTerminal removes underlines when its window resigns key.
        restoreCueUnderline()
    }

    // Whether window belongs to the open popover (the popover itself or one of its popups).
    private func ownsWindow(_ window: NSWindow?) -> Bool {
        guard let window, let viewController = popover?.contentViewController else {
            return false
        }
        if viewController.isViewLoaded && viewController.view.window === window {
            return true
        }
        if let browser = viewController as? iTermBrowserQuickLookViewController {
            return browser.owns(window: window)
        }
        return false
    }

    private func anchorRect(forPointInWindow pointInWindow: NSPoint) -> NSRect {
        guard let view, let host else {
            return .zero
        }
        let cellSize = host.webQuickLookCellSize()
        let rect = NSRect(x: pointInWindow.x - cellSize.width / 2,
                          y: pointInWindow.y - cellSize.height / 2,
                          width: cellSize.width,
                          height: cellSize.height)
        return view.convert(rect, from: nil)
    }

    private func showBrowserPopover(atPointInWindow pointInWindow: NSPoint,
                                    url: URL,
                                    hoverAllowlist: iTermQuickLookDomainAllowlist?) -> NSPopover? {
        // NSPopover raises for a positioning view with no window.
        guard let view, view.window != nil else {
            return nil
        }
        let viewController = iTermBrowserQuickLookViewController(url: url, hoverAllowlist: hoverAllowlist)
        let popover = NSPopover()
        popover.contentViewController = viewController
        popover.contentSize = viewController.view.frame.size
        viewController.presentingPopover = popover
        viewController.onPointerEntered = { [weak self] in
            self?.controller?.pointerEnteredPreview()
        }
        viewController.onPointerExited = { [weak self] in
            guard let self else {
                return
            }
            self.controller?.pointerLeftPreview(at: self.pointerLocation())
        }
        popover.behavior = .semitransient
        popover.delegate = self
        popover.show(relativeTo: anchorRect(forPointInWindow: pointInWindow),
                     of: view,
                     preferredEdge: .minY)
        return popover
    }

    private func showLegacyPopover(atPointInWindow pointInWindow: NSPoint, url: URL) -> NSPopover? {
        // NSPopover raises for a positioning view with no window.
        guard let view, view.window != nil,
              let webView = iTermWebViewFactory.sharedInstance().webView(with: nil),
              let viewController = iTermWebViewWrapperViewController(webView: webView, backupURL: url) else {
            return nil
        }
        webView.load(URLRequest(url: url))
        let popover = NSPopover()
        popover.contentViewController = viewController
        popover.contentSize = viewController.view.frame.size
        popover.behavior = .semitransient
        popover.delegate = self
        popover.show(relativeTo: anchorRect(forPointInWindow: pointInWindow),
                     of: view,
                     preferredEdge: .minY)
        return popover
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        guard let closed = notification.object as? NSPopover else {
            return
        }
        Self.tearDownContent(of: closed)
        guard closed === popover else {
            return
        }
        DLog("Web Quick Look \(closed) was closed")
        let openedByHover = popoverOpenedByHover
        setPopover(nil, openedByHover: false)
        if openedByHover {
            controller?.previewClosed()
        }
    }

    // MARK: - Events from the text view. These only observe events: they never consume or alter them.

    @objc var wantsMouseMovementEvents: Bool {
        if Self.currentMode == .hover {
            return true
        }
        // In ⌘ + Hover mode, holding Cmd already turns on mouse-moved events, but auto-close must
        // also see the pointer leave after Cmd is released.
        return hasHoverOpenedPreview
    }

    private var windowIsActive: Bool {
        return view?.window?.isKeyWindow == true && NSApp.isActive
    }

    @objc(mouseMoved:)
    func mouseMoved(_ event: NSEvent) {
        guard let view,
              let controller = controllerCreatingIfNeeded(),
              event.window === view.window,
              !hasDeliberatelyOpenedPreview else {
            // While a force-press or menu preview is open the controller is idle, and hover must
            // not replace that preview, so there is nothing to schedule.
            return
        }
        let flags = event.it_modifierFlags
        controller.pointerMoved(to: view.convert(event.locationInWindow, from: nil),
                                commandDown: flags.contains(.command),
                                optionDown: flags.contains(.option),
                                windowActive: windowIsActive)
    }

    @objc(flagsChanged:)
    func flagsChanged(_ event: NSEvent) {
        guard let controller = controllerCreatingIfNeeded() else {
            return
        }
        let flags = event.it_modifierFlags
        let commandDown = flags.contains(.command)
        let optionDown = flags.contains(.option)
        controller.modifiersChanged(commandDown: commandDown, optionDown: optionDown)
        guard mode == .commandHover,
              commandDown,
              !optionDown,
              let view,
              let window = view.window,
              !hasDeliberatelyOpenedPreview else {
            return
        }
        // Pressing Cmd while the pointer rests on a link counts as arriving there with Cmd held.
        let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard view.visibleRect.contains(point) else {
            return
        }
        controller.pointerMoved(to: point,
                                commandDown: commandDown,
                                optionDown: optionDown,
                                windowActive: windowIsActive)
    }

    @objc func mouseDown() {
        controller?.mouseDown()
    }

    @objc func keyDown() {
        controller?.keyDown()
    }

    @objc func scrolled() {
        controller?.scrolled()
    }

    // Called after each refresh with whether the content moved (overflow, screen scroll, resize) and
    // whether anything was redrawn. A switch between the main and alternate screens since the last
    // refresh also counts as a shift.
    @objc(refreshedWithContentShifted:changed:)
    func refreshed(contentShifted shifted: Bool, changed: Bool) {
        // Switching screens (a full-screen program starting or exiting) without scrolling only marks
        // cells dirty, but the text under the pointer is all new, so it counts as a shift.
        let showingAlternateScreen = host?.webQuickLookShowingAlternateScreen() ?? false
        let switchedScreens = showingAlternateScreen != lastShowedAlternateScreen
        lastShowedAlternateScreen = showingAlternateScreen
        if shifted || switchedScreens {
            controller?.contentShifted()
        }
        if changed || switchedScreens {
            controller?.contentChanged()
            updateCueURLBar()
        }
    }

    // The app lost focus.
    @objc func deactivated() {
        controller?.deactivated()
    }

    // The view is leaving its window (another tab, a closed or moved session). A pending hover
    // open must not fire on it, and a popover anchored to it can't stay.
    @objc(viewWillMoveToWindow:)
    func viewWillMove(toWindow newWindow: NSWindow?) {
        guard newWindow !== view?.window else {
            return
        }
        controller?.deactivated()
        guard popover != nil else {
            return
        }
        let openedByHover = popoverOpenedByHover
        close()
        if openedByHover {
            controller?.previewClosed()
        }
    }

    // The text view lost keyboard focus, for example to another split pane. Drops a pending hover
    // cue, but not the cue of an open hover preview, then removes the underline.
    @objc func textViewResignedFirstResponder() {
        // A pending cue would otherwise come back on the next underline update in this view, and a
        // pending open would still fire. The controller keeps the cue of an open hover preview.
        if let controller {
            controller.focusLost()
        } else if !cueBelongsToOpenPreview {
            clearCue()
        }
        _ = removeUnderlineForFocusChange()
    }

    @objc func textViewBecameFirstResponder() {
        restoreCueUnderline()
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        guard controller != nil, let window = view?.window, notification.object as? NSWindow === window else {
            return
        }
        // The new key window isn't known yet. If it turns out to be the preview itself (the user
        // clicked into it) or one of its sign-in popups, the terminal didn't really lose focus.
        DispatchQueue.main.async { [weak self] in
            self?.checkWindowDeactivation()
        }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = view?.window, notification.object as? NSWindow === window else {
            return
        }
        restoreCueUnderline()
    }

    private func checkWindowDeactivation() {
        if view?.window?.isKeyWindow == true || ownsWindow(NSApp.keyWindow) {
            return
        }
        DLog("Window resigned key; deactivate Quick Look hover")
        deactivated()
    }

    // MARK: - Underlines

    private var cueBelongsToOpenPreview: Bool {
        return cueURL != nil && hasHoverOpenedPreview
    }

    // Like removing the underline, but leaves the hover cue's underline in place.
    @discardableResult
    @objc func removeUnderlineExceptCue() -> Bool {
        guard let host else {
            return false
        }
        guard cueURL != nil, iTermAdvancedSettingsModel.enableUnderlineSemanticHistoryOnCmdHover() else {
            return host.webQuickLookRemoveUnderline()
        }
        if VT100GridAbsWindowedRangeEquals(host.webQuickLookUnderlinedRange(), cueUnderlinedRange) {
            return false
        }
        host.webQuickLookSetUnderlinedRange(cueUnderlinedRange)
        return true
    }

    // Removes the underline because the view or its window lost focus, but keeps the hover cue’s
    // underline while the preview it marks is open: opening that preview can take key briefly.
    @discardableResult
    @objc func removeUnderlineForFocusChange() -> Bool {
        if cueBelongsToOpenPreview {
            DLog("Focus changed; keeping the hover cue underline for \(cueURL ?? "")")
            return removeUnderlineExceptCue()
        }
        return host?.webQuickLookRemoveUnderline() ?? false
    }

    // Puts the hover cue’s underline back if a focus change removed it while its preview is open.
    func restoreCueUnderline() {
        guard cueBelongsToOpenPreview else {
            return
        }
        if removeUnderlineExceptCue() {
            DLog("Restored the hover cue underline for \(cueURL ?? "")")
        }
    }

    // MARK: - The hover cue

    // The pending cue's URL and where its URL bar goes, for when nothing else wants the URL bar. Nil
    // once a preview shows (its own address bar has the URL) or the link scrolled out of the buffer.
    @objc(pendingCueURLWithAnchor:)
    func pendingCueURL(anchor: UnsafeMutablePointer<VT100GridWindowedRange>) -> String? {
        guard let cueURL, !hasHoverOpenedPreview, let cueAnchor = cueAnchor() else {
            return nil
        }
        anchor.pointee = cueAnchor
        return cueURL
    }

    // The cue's link in current visual coordinates. Nil once the link has scrolled out of the
    // buffer.
    func cueAnchor() -> VT100GridWindowedRange? {
        var valid = ObjCBool(false)
        let anchor = VT100GridWindowedRangeFromAbsWindowedRangeSafe(cueAbsVisualRange,
                                                                    host?.webQuickLookTotalScrollbackOverflow() ?? 0,
                                                                    &valid)
        return valid.boolValue ? anchor : nil
    }

    // Shows the hover cue (underline and URL bar) for the last resolved link.
    func showCue(for url: URL) {
        guard let host else {
            return
        }
        guard url == resolvedURL else {
            DLog("Not showing hover cue for \(url): last resolved \(String(describing: resolvedURL))")
            return
        }
        DLog("Show hover cue for \(url)")
        let overflow = host.webQuickLookTotalScrollbackOverflow()
        let cueURL = url.absoluteString
        self.cueURL = cueURL
        cueAbsVisualRange = resolvedAbsVisualRange
        cueUnderlinedRange = resolvedUnderlinedRange
        if iTermAdvancedSettingsModel.enableUnderlineSemanticHistoryOnCmdHover() {
            host.webQuickLookSetUnderlinedRange(cueUnderlinedRange)
        }
        if hasHoverOpenedPreview && url == previewLinkURL {
            // Another occurrence of the open preview's link.
            previewLinkAbsVisualRange = cueAbsVisualRange
        }
        if hasHoverOpenedPreview {
            // The open preview’s address bar shows the URL.
            return
        }
        var valid = ObjCBool(false)
        let anchor = VT100GridWindowedRangeFromAbsWindowedRangeSafe(cueAbsVisualRange, overflow, &valid)
        showCueURLBar(cueURL, anchor: anchor)
    }

    private func showCueURLBar(_ url: String, anchor: VT100GridWindowedRange) {
        lastShownCueAnchor = anchor
        host?.webQuickLookShowHoverURL(url, anchor: anchor)
    }

    private var commandIsDown: Bool {
        return iTermApplication.shared().it_modifierFlags.contains(.command)
    }

    // Moves the pending cue's URL bar to where its link is now, so the bar follows the link as
    // output scrolls, and hides it once the link has scrolled out of the buffer. Leaves the bar
    // alone when there is no pending cue or Cmd-hover owns it.
    private func updateCueURLBar() {
        guard let cueURL, !hasHoverOpenedPreview, !commandIsDown else {
            return
        }
        guard let anchor = cueAnchor() else {
            hideCueURLBar()
            return
        }
        if let lastShownCueAnchor,
           VT100GridCoordRangeEqualsCoordRange(lastShownCueAnchor.coordRange, anchor.coordRange),
           lastShownCueAnchor.columnWindow.location == anchor.columnWindow.location,
           lastShownCueAnchor.columnWindow.length == anchor.columnWindow.length {
            return
        }
        showCueURLBar(cueURL, anchor: anchor)
    }

    func clearCue() {
        guard let cueURL, let host else {
            return
        }
        DLog("Clear hover cue for \(cueURL)")
        self.cueURL = nil
        if VT100GridAbsWindowedRangeEquals(host.webQuickLookUnderlinedRange(), cueUnderlinedRange) {
            _ = host.webQuickLookRemoveUnderline()
        }
        hideCueURLBar()
    }

    // Hides the URL bar the hover cue showed.
    private func hideCueURLBar() {
        // With Cmd down the Cmd-hover cue owns the URL bar.
        guard !commandIsDown else {
            return
        }
        lastShownCueAnchor = nil
        host?.webQuickLookShowHoverURL(nil,
                                       anchor: VT100GridWindowedRangeMake(VT100GridCoordRangeMake(-1, -1, -1, -1), -1, -1))
    }

    // MARK: - Finding links

    // The content cell at a point, with the lines dropped off the top counted in, so a cell keeps
    // its number while lines scroll off.
    func absoluteCell(at point: NSPoint) -> VT100GridAbsCoord {
        guard let host else {
            return VT100GridAbsCoordMake(0, 0)
        }
        let coord = host.webQuickLookCoord(for: point, allowRightMarginOverflow: false)
        return VT100GridAbsCoordFromCoord(coord, host.webQuickLookTotalScrollbackOverflow())
    }

    // The same cell, and whether it is on the alternate screen, which numbers its lines like the
    // main screen.
    func cell(at point: NSPoint) -> iTermQuickLookHoverCell {
        let coord = absoluteCell(at: point)
        return iTermQuickLookHoverCell(line: coord.y,
                                       column: coord.x,
                                       alternateScreen: host?.webQuickLookShowingAlternateScreen() ?? false)
    }

    // `overflow` is the scrollback overflow when the action was looked up, which its relative
    // ranges are measured against.
    private func recordResolution(url: URL, action: URLAction, overflow: Int64) {
        resolvedURL = url
        resolvedAbsVisualRange = VT100GridAbsWindowedRangeFromRelative(action.visualRange, overflow)
        resolvedUnderlinedRange = VT100GridAbsWindowedRangeFromRelative(action.logicalRange, overflow)
    }

    // Looks up the OSC 8 hyperlink at point without semantic history, smart selection or
    // filesystem work, so the hover cue can show on the move that enters the link, and records it
    // as the last resolution. Unknown when only the full resolution can tell, which is for
    // plain-text URLs when hover includes them.
    func immediateLink(at point: NSPoint, includesPlainTextURLs: Bool) -> iTermQuickLookHoverImmediateLookup {
        guard let host else {
            return .unknown
        }
        let requestCoord = host.webQuickLookCoord(for: point, allowRightMarginOverflow: true)
        let coord = host.webQuickLookCoord(for: point, allowRightMarginOverflow: false)
        guard let action = host.webQuickLookURLActionHelper().hypertextLinkAction(at: requestCoord) else {
            return includesPlainTextURLs ? .unknown : .noLink([])
        }
        guard VT100GridWindowedRangeContainsCoord(action.visualRange, coord) else {
            return .noLink([])
        }
        let rects = self.rects(for: action.visualRange)
        guard let url = host.webQuickLookURL(for: action) else {
            // Its extent lets the controller skip this link on the moves that follow.
            return .noLink(rects)
        }
        recordResolution(url: url, action: action, overflow: host.webQuickLookTotalScrollbackOverflow())
        return .link(url, rects)
    }

    // Resolves the link at point. Calls completion with an http(s) URL and the rects the link
    // occupies, or with nil when the point isn't on a web link.
    private func resolveLink(at point: NSPoint, completion: @escaping (URL?, [NSRect]) -> Void) {
        guard let host else {
            completion(nil, [])
            return
        }
        let requestCoord = host.webQuickLookCoord(for: point, allowRightMarginOverflow: true)
        let coord = host.webQuickLookCoord(for: point, allowRightMarginOverflow: false)
        cancelPendingResolution()
        let expectedGeneration = resolutionGeneration
        // The answer is in the coordinates of the moment of asking.
        let overflow = host.webQuickLookTotalScrollbackOverflow()
        pendingResolution = host.webQuickLookURLActionHelper().urlActionForClick(at: requestCoord) { [weak self] action in
            guard let self, self.resolutionGeneration == expectedGeneration else {
                // Stale. The controller dropped this resolution, so it needs no answer.
                return
            }
            self.pendingResolution = nil
            guard let host = self.host,
                  let action,
                  action.actionType == .openURL,
                  VT100GridWindowedRangeContainsCoord(action.visualRange, coord) else {
                completion(nil, [])
                return
            }
            guard Self.shouldHoverPreview(isOSC8: action.osc8, includesPlainTextURLs: Self.includesPlainTextURLs) else {
                DLog("Not previewing \(action.string ?? "") on hover: not an OSC 8 hyperlink")
                completion(nil, [])
                return
            }
            guard let url = host.webQuickLookURL(for: action) else {
                completion(nil, [])
                return
            }
            self.recordResolution(url: url, action: action, overflow: overflow)
            completion(url, self.rects(for: action.visualRange))
        }
    }

    // The rects, in the view's coordinates, that the cells of a visual range cover: one per line.
    private func rects(for range: VT100GridWindowedRange) -> [NSRect] {
        guard let host else {
            return []
        }
        var left = Int32(0)
        var right = host.webQuickLookGridWidth()
        if range.columnWindow.length > 0 {
            left = range.columnWindow.location
            right = range.columnWindow.location + range.columnWindow.length
        }
        let yOffset = host.webQuickLookVerticalOffset()
        let sideMargins = CGFloat(iTermPreferences.sideMargins())
        let cellSize = host.webQuickLookCellSize()
        var rects = [NSRect]()
        for y in range.coordRange.start.y...max(range.coordRange.start.y, range.coordRange.end.y) where y <= range.coordRange.end.y {
            let startX = y == range.coordRange.start.y ? range.coordRange.start.x : left
            let endX = y == range.coordRange.end.y ? range.coordRange.end.x : right
            if endX <= startX {
                continue
            }
            rects.append(NSRect(x: sideMargins + CGFloat(startX) * cellSize.width,
                                y: CGFloat(y) * cellSize.height + yOffset,
                                width: CGFloat(endX - startX) * cellSize.width,
                                height: cellSize.height))
        }
        return rects
    }

    // Where the pointer is now in the view's coordinates, or nil when it is outside the visible
    // part. Read from the window rather than from the last mouse event, because when output scrolls
    // the view moves under a still pointer.
    private func pointerLocation() -> NSPoint? {
        if let pointerLocationForTesting {
            return pointerLocationForTesting
        }
        guard let view, let window = view.window else {
            return nil
        }
        let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard view.visibleRect.contains(point) else {
            return nil
        }
        return point
    }

    private var previewFrame: NSRect? {
        guard let view,
              let window = view.window,
              let viewController = popover?.contentViewController,
              viewController.isViewLoaded,
              let previewWindow = viewController.view.window else {
            return nil
        }
        let frame = view.convert(window.convertFromScreen(previewWindow.frame), from: nil)
        return frame.isEmpty ? nil : frame
    }

    // MARK: - iTermQuickLookHoverControllerDelegate

    func hoverControllerResolveLink(at point: NSPoint, completion: @escaping (URL?, [NSRect]) -> Void) {
        resolveLink(at: point, completion: completion)
    }

    func hoverControllerLookUpLinkImmediately(at point: NSPoint) -> iTermQuickLookHoverImmediateLookup {
        return immediateLink(at: point, includesPlainTextURLs: Self.includesPlainTextURLs)
    }

    func hoverControllerOpenPreview(url: URL, linkRects: [NSRect], at point: NSPoint) -> Bool {
        guard let view else {
            return false
        }
        // The open timer was started while the window was active and showed this view. Either may
        // have changed without an event reaching this view, for example when a key equivalent
        // switches tabs or the session ends.
        guard view.window != nil, !view.isHiddenOrHasHiddenAncestor, windowIsActive else {
            DLog("Not opening \(url) on hover: the view is not in the active window")
            return false
        }
        if hasDeliberatelyOpenedPreview {
            DLog("Not opening \(url) on hover: a force-press or menu preview is open")
            return false
        }
        show(url: url, atPointInWindow: view.convert(point, to: nil), openedByHover: true)
        hideCueURLBar()
        if url == resolvedURL {
            previewLinkURL = url
            previewLinkAbsVisualRange = resolvedAbsVisualRange
        } else {
            previewLinkURL = nil
        }
        return true
    }

    func hoverControllerClosePreview() {
        if popoverOpenedByHover {
            close()
        }
    }

    func hoverControllerPreviewFrame() -> NSRect? {
        return previewFrame
    }

    func hoverControllerShowCue(url: URL, linkRects: [NSRect]) {
        showCue(for: url)
    }

    func hoverControllerClearCue() {
        clearCue()
    }

    func hoverControllerPointerLocation() -> NSPoint? {
        return pointerLocation()
    }

    func hoverControllerCell(at point: NSPoint) -> iTermQuickLookHoverCell {
        return cell(at: point)
    }

    // A dropped resolution must not finish and replace the recorded link (resolvedURL and its
    // ranges), which the cue and the open preview rely on.
    func hoverControllerCancelResolution() {
        cancelPendingResolution()
    }

    private func cancelPendingResolution() {
        resolutionGeneration += 1
        pendingResolution?.cancelOperation()
        pendingResolution = nil
    }

    // Offers to add the link's domain to the allowlist, once per domain per view.
    func hoverControllerDeclinedLink(url: URL) {
        guard let domain = iTermQuickLookDomainAllowlist.domainToOffer(for: url),
              !offeredDomains.contains(domain),
              !iTermUserDefaults.userDefaults().bool(forKey: Self.neverOfferToAllowDomainKey) else {
            return
        }
        offeredDomains.insert(domain)
        DLog("Offer to allow hover previews of \(domain)")
        let title = String(localized: "WebQuickLook.OfferToAllowDomain",
                           defaultValue: "Links to \(domain) don’t preview on hover because it isn’t one of your allowed domains.",
                           comment: "Announcement shown after the pointer rested on a link that didn’t preview because its domain isn’t in the hover allowlist. The placeholder is the domain, such as github.com.")
        let actions = [String(localized: "WebQuickLook.AllowDomain",
                              defaultValue: "Allow \(domain)",
                              comment: "Button that adds a domain to the list of domains Quick Look previews on hover. The placeholder is the domain, such as github.com."),
                       String(localized: "WebQuickLook.DontAskAgain",
                              defaultValue: "Don’t Ask Again",
                              comment: "Button that stops offering to add domains to the list of domains Quick Look previews on hover")]
        let completion: (Int32) -> Void = { selection in
            switch selection {
            case 0:
                iTermQuickLookDomainAllowlist.saveDomain(domain)
            case 1:
                iTermUserDefaults.userDefaults().set(true, forKey: Self.neverOfferToAllowDomainKey)
            default:
                break
            }
        }
        guard let announcement = iTermAnnouncementViewController.announcement(withTitle: title,
                                                                              style: .kiTermAnnouncementViewStyleQuestion,
                                                                              withActions: actions,
                                                                              completion: completion) else {
            return
        }
        host?.webQuickLookQueue(announcement, identifier: Self.announcementIdentifier)
    }

    func hoverControllerPreviewLinkRects() -> [NSRect]? {
        guard hasHoverOpenedPreview, previewLinkURL != nil, let host else {
            return nil
        }
        var valid = ObjCBool(false)
        let range = VT100GridWindowedRangeFromAbsWindowedRangeSafe(previewLinkAbsVisualRange,
                                                                   host.webQuickLookTotalScrollbackOverflow(),
                                                                   &valid)
        return valid.boolValue ? rects(for: range) : []
    }
}
