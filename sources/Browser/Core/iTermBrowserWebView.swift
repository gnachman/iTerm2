//
//  iTermBrowserWebView.swift
//  iTerm2
//
//  Created by George Nachman on 6/19/25.
//

import WebKit

@available(macOS 11.0, *)
@objc protocol iTermBrowserWebViewDelegate: AnyObject {
    func webViewDidRequestViewSource(_ webView: iTermBrowserWebView)
    func webViewDidRequestSavePageAs(_ webView: iTermBrowserWebView)
    func webViewDidRequestCopyPageTitle(_ webView: iTermBrowserWebView)

    // Should update self.variablesScope.mouseInfo
    func webViewSetMouseInfo(
        _ webView: iTermBrowserWebView,
        pointInView: NSPoint,
        button: Int,
        count: Int,
        modifiers: NSEvent.ModifierFlags,
        sideEffects: iTermClickSideEffects,
        state: iTermMouseState)

    func webViewDidRequestDoSmartSelection(_ webView: iTermBrowserWebView,
                                           pointInWindow point: NSPoint)
    func webViewOpenURLInNewTab(_ webView: iTermBrowserWebView, url: URL)
    func webViewDidHoverURL(_ webView: iTermBrowserWebView, url: String?, frame: NSRect)
}

@available(macOS 11.0, *)
class iTermBrowserWebView: WKWebView {
    weak var browserDelegate: iTermBrowserWebViewDelegate?
    var deferrableInteractionState: Any?
    private let pointerController: PointerController
    private var threeFingerTapGestureRecognizer: ThreeFingerTapGestureRecognizer!
    private var mouseDownIsThreeFingerClick = false  // TODO
    private var numTouches = 0  // TODO
    private var mouseDown = false  // TODO
    private var mouseDownLocationInWindow: NSPoint?
    private var hoverLinkSecret: String?

    init(frame: CGRect,
         configuration: WKWebViewConfiguration,
         pointerController: PointerController) {
        self.pointerController = pointerController
        super.init(frame: frame, configuration: configuration)
        allowsMagnification = true
        threeFingerTapGestureRecognizer = ThreeFingerTapGestureRecognizer(target: self,
                                                                          selector: #selector(threeFingerTap(_:)))
        allowedTouchTypes = .indirect
        wantsRestingTouches = true
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    deinit {
        threeFingerTapGestureRecognizer.disconnectTarget()
    }

    @objc(threeFingerTap:)
    private func threeFingerTap(_ event: NSEvent) {
        if !pointerController.threeFingerTap(event) {
            sendFakeThreeFingerClick(down: true, event: event)
            sendFakeThreeFingerClick(down: false, event: event)
        }
    }

    private func sendFakeThreeFingerClick(down: Bool, event: NSEvent) {
        guard let fakeEvent = down ? event.mouseDownEventFromGesture : event.mouseUpEventFromGesture else {
            return
        }
        let saved = numTouches
        numTouches = 3
        if down {
            mouseDown(with: fakeEvent)
        } else {
            mouseUp(with: fakeEvent)
        }
        numTouches = saved
    }

    // MARK: - NSView

    override func touchesBegan(with event: NSEvent) {
        numTouches = event.touches(matching: [.began, .stationary],
                                   in: self).count
        threeFingerTapGestureRecognizer.touchesBegan(with: event)
        super.touchesBegan(with: event)
    }

    override func touchesEnded(with event: NSEvent) {
        numTouches = event.touches(matching: [.stationary],
                                   in: self).count
        threeFingerTapGestureRecognizer.touchesEnded(with: event)
        super.touchesEnded(with: event)
    }

    override func touchesMoved(with event: NSEvent) {
        threeFingerTapGestureRecognizer.touchesMoved(with: event)
        super.touchesMoved(with: event)
    }

    override func touchesCancelled(with event: NSEvent) {
        numTouches = 0
        threeFingerTapGestureRecognizer.touchesCancelled(with: event)
        super.touchesCancelled(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if threeFingerTapGestureRecognizer.mouseDown(event) {
            return
        }
        let (callSuper, sideEffects) = mouseDownImpl(event: event)
        if callSuper {
            super.mouseDown(with: event)
        }
        if sideEffects != [.ignore] {
            setMouseInfo(event: event, sideEffects: sideEffects)
        }
    }

    private func mouseDownImpl(event: NSEvent) -> (Bool, iTermClickSideEffects) {
        var sideEffects: iTermClickSideEffects = []
        pointerController.notifyLeftMouseDown()
        mouseDownIsThreeFingerClick = false
        if numTouches == 3 {
            var shouldReturnEarly = false
            if iTermPreferences.bool(forKey: kPreferenceKeyThreeFingerEmulatesMiddle) {
                emulateThirdButton(pressDown: true, with: event)
                sideEffects = [.ignore]
            } else {
                shouldReturnEarly = pointerController.mouseDown(
                    event,
                    withTouches: Int32(numTouches),
                    ignoreOption: false,
                    reportable: false)
                if shouldReturnEarly {
                    sideEffects.insert(.performBoundAction)
                }
                mouseDown = true
            }
            if shouldReturnEarly {
                return (false, sideEffects)
            }
        }
        if pointerController.eventEmulatesRightClick(event, reportable: false) {
            if pointerController.mouseDown(
                event,
                withTouches: Int32(numTouches),
                ignoreOption: false,
                reportable: false) {
                sideEffects.insert(.performBoundAction)
            }
            return (false, sideEffects)
        }
        mouseDown = true
        mouseDownLocationInWindow = event.locationInWindow

        let ssClicks = if iTermPreferences.bool(forKey: kPreferenceKeyDoubleClickPerformsSmartSelection) {
            2
        } else {
            4
        }
        if event.clickCount == ssClicks {
            browserDelegate?.webViewDidRequestDoSmartSelection(self, pointInWindow: event.locationInWindow)
            sideEffects.insert(.modifySelection)
            return (false, sideEffects)
        }
        return (true, sideEffects)
    }

    private func emulateThirdButton(pressDown: Bool, with event: NSEvent) {
        guard let fakeEvent = event.withButtonNumber(2) else {
            return
        }
        let saved = numTouches
        numTouches = 1
        if pressDown {
            otherMouseDown(with: fakeEvent)
        } else {
            otherMouseUp(with: fakeEvent)
        }
        numTouches = saved
        if !pressDown {
            mouseDownIsThreeFingerClick = false
        }
    }

    private func focusOnRightOrMiddleClickIfNeeded() {
        if iTermPreferences.bool(forKey: kPreferenceKeyFocusOnRightOrMiddleClick) {
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(self)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    override func rightMouseDown(with event: NSEvent) {
        focusOnRightOrMiddleClickIfNeeded()
        if threeFingerTapGestureRecognizer.rightMouseDown(event) {
            return
        }
        if pointerController.mouseDown(event,
                                       withTouches: Int32(numTouches),
                                       ignoreOption: false,
                                       reportable: false) {
            setMouseInfo(event: event,
                         sideEffects: iTermClickSideEffects.performBoundAction)
            return
        }
        super.rightMouseDown(with: event)
        setMouseInfo(event: event, sideEffects: [])
    }

    override func otherMouseDown(with event: NSEvent) {
        focusOnRightOrMiddleClickIfNeeded()
        let sideEffects: iTermClickSideEffects = if pointerController.mouseDown(
            event,
            withTouches: Int32(numTouches),
            ignoreOption: false,
            reportable: false) {
            [.performBoundAction]
        } else {
            []
        }
        setMouseInfo(event: event, sideEffects: sideEffects)
        super.otherMouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let sideEffects = mouseUpImpl(with: event)
        if sideEffects != [.ignore] {
            setMouseInfo(event: event, sideEffects: sideEffects)
        }
        super.mouseUp(with: event)
    }

    private func mouseUpImpl(with event: NSEvent) -> iTermClickSideEffects {
        if threeFingerTapGestureRecognizer.mouseUp(event) {
            return []
        }
        let savedNumTouches = numTouches
        numTouches = 0
        if mouseDownIsThreeFingerClick {
            emulateThirdButton(pressDown: false, with: event)
            return []
        }
        if savedNumTouches == 3 && mouseDown {
            let performedAction = pointerController.mouseUp(
                event,
                withTouches: Int32(numTouches),
                reportable: false)
            mouseDown = false
            return performedAction ? [.performBoundAction] :  []
        }
        if pointerController.eventEmulatesRightClick(event, reportable: false) {
            let performedAction = pointerController.mouseUp(
                event,
                withTouches: Int32(numTouches),
                reportable: false)
            return performedAction ? [.performBoundAction] : []
        }
        if !mouseDown {
            return [.ignore]
        }
        mouseDown = false

        super.mouseUp(with: event)
        setMouseInfo(event: event, sideEffects: [])
        
        // Check if copy-on-select is enabled and copy selection if it exists
        if iTermPreferences.bool(forKey: kPreferenceKeySelectionCopiesText) {
            Task {
                await copySelectionToClipboard()
            }
        }
        
        return []
    }

    override func rightMouseUp(with event: NSEvent) {
        if threeFingerTapGestureRecognizer.rightMouseUp(event) {
            return
        }
        if pointerController.mouseUp(event, withTouches: Int32(numTouches), reportable: false) {
            setMouseInfo(event: event, sideEffects: [.performBoundAction])
            return
        }
        super.rightMouseUp(with: event)
        setMouseInfo(event: event, sideEffects: [])
    }

    override func otherMouseUp(with event: NSEvent) {
        if !mouseDownIsThreeFingerClick {
            super.otherMouseUp(with: event)
        }
        let sideEffects: iTermClickSideEffects = if pointerController.mouseUp(
            event,
            withTouches: Int32(numTouches),
            reportable: false) {
            [.performBoundAction]
        } else {
            []
        }
        setMouseInfo(event: event, sideEffects: sideEffects)
    }

    override func mouseDragged(with event: NSEvent) {
        let sideEffects = mouseDraggedImpl(with: event)
        if sideEffects != [.ignore] {
            setMouseInfo(event: event, sideEffects: sideEffects)
            super.mouseDragged(with: event)
        }
    }

    private func mouseDraggedImpl(with event: NSEvent) -> iTermClickSideEffects {
        threeFingerTapGestureRecognizer.mouseDragged()
        if let mouseDownLocation = mouseDownLocationInWindow {
            let locationInWindow = event.locationInWindow
            let euclideanDistance = { (p1: NSPoint, p2: NSPoint) in
                return sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2));
            }
            let dragDistance = euclideanDistance(mouseDownLocation, locationInWindow)
            let dragThreshold = 3.0
            if dragDistance > dragThreshold {
                mouseDownIsThreeFingerClick = false
            }
        }
        if mouseDownIsThreeFingerClick {
            return [.ignore]
        }
        return []
    }

    override func rightMouseDragged(with event: NSEvent) {
        threeFingerTapGestureRecognizer.mouseDragged()
        super.rightMouseDragged(with: event)
        setMouseInfo(event: event, sideEffects: [])
    }

    override func otherMouseDragged(with event: NSEvent) {
        threeFingerTapGestureRecognizer.mouseDragged()
        super.otherMouseDragged(with: event)
        setMouseInfo(event: event, sideEffects: [])
    }

    override func scrollWheel(with event: NSEvent) {
        threeFingerTapGestureRecognizer.scrollWheel()
        super.scrollWheel(with: event)
    }

    override func pressureChange(with event: NSEvent) {
        pointerController.pressureChange(with: event)
        super.pressureChange(with: event)
    }

    override func swipe(with event: NSEvent) {
        pointerController.swipe(with: event)
        super.swipe(with: event)
    }

    private func setMouseInfo(event: NSEvent, sideEffects: iTermClickSideEffects) {
        let state: iTermMouseState
        switch event.type {
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            state = .up
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            state = .down
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            state = .drag
        default:
            return
        }
        browserDelegate?.webViewSetMouseInfo(
            self,
            pointInView: convert(event.locationInWindow, from: nil),
            button: event.buttonNumber,
            count: event.clickCount,
            modifiers: event.it_modifierFlags,
            sideEffects: sideEffects,
            state: state)
    }

    // MARK: - Deferred Interaction State
    
    @available(macOS 12.0, *)
    @discardableResult
    func applyDeferredInteractionStateIfNeeded() -> Bool {
        guard let deferred = deferrableInteractionState else { return false }

        DLog("Applying deferred interaction state")
        deferrableInteractionState = nil
        interactionState = deferred
        return true
    }
    
    // MARK: - Override navigation methods to apply deferred state
    
    @discardableResult
    override func load(_ request: URLRequest) -> WKNavigation? {
        if #available(macOS 12.0, *) {
            applyDeferredInteractionStateIfNeeded()
        }
        return super.load(request)
    }
    
    @discardableResult
    override func loadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation? {
        if #available(macOS 12.0, *) {
            applyDeferredInteractionStateIfNeeded()
        }
        return super.loadHTMLString(string, baseURL: baseURL)
    }
    
    @discardableResult
    override func load(_ data: Data, mimeType MIMEType: String, characterEncodingName: String, baseURL: URL) -> WKNavigation? {
        if #available(macOS 12.0, *) {
            applyDeferredInteractionStateIfNeeded()
        }
        return super.load(data, mimeType: MIMEType, characterEncodingName: characterEncodingName, baseURL: baseURL)
    }
    
    @discardableResult
    override func loadFileURL(_ URL: URL, allowingReadAccessTo readAccessURL: URL) -> WKNavigation? {
        if #available(macOS 12.0, *) {
            applyDeferredInteractionStateIfNeeded()
        }
        return super.loadFileURL(URL, allowingReadAccessTo: readAccessURL)
    }
    
    @discardableResult
    override func reload() -> WKNavigation? {
        if #available(macOS 12.0, *) {
            applyDeferredInteractionStateIfNeeded()
        }
        return super.reload()
    }
    
    @discardableResult
    override func reloadFromOrigin() -> WKNavigation? {
        if #available(macOS 12.0, *) {
            applyDeferredInteractionStateIfNeeded()
        }
        return super.reloadFromOrigin()
    }
    
    @discardableResult
    override func goBack() -> WKNavigation? {
        if #available(macOS 12.0, *) {
            applyDeferredInteractionStateIfNeeded()
        }
        return super.goBack()
    }
    
    @discardableResult
    override func goForward() -> WKNavigation? {
        if #available(macOS 12.0, *) {
            applyDeferredInteractionStateIfNeeded()
        }
        return super.goForward()
    }
    
    @discardableResult
    override func go(to item: WKBackForwardListItem) -> WKNavigation? {
        if #available(macOS 12.0, *) {
            applyDeferredInteractionStateIfNeeded()
        }
        return super.go(to: item)
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)

        // Add separator before our custom items
        menu.addItem(NSMenuItem.separator())
        
        // Add Save Page As menu item
        let savePageItem = NSMenuItem(title: "Save Page As…", action: #selector(savePageAsMenuClicked), keyEquivalent: "")
        savePageItem.target = self
        menu.addItem(savePageItem)
        
        // Add Print Page menu item
        let printPageItem = NSMenuItem(title: "Print…", action: #selector(printView(_:)), keyEquivalent: "")
        printPageItem.target = self
        menu.addItem(printPageItem)
        
        // Add Copy Page Title menu item
        let copyTitleItem = NSMenuItem(title: "Copy Page Title", action: #selector(copyPageTitleMenuClicked), keyEquivalent: "")
        copyTitleItem.target = self
        menu.addItem(copyTitleItem)

        menu.addItem(NSMenuItem.separator())

        // Add View Source menu item
        let viewSourceItem = NSMenuItem(title: "View Source", action: #selector(viewSourceMenuClicked), keyEquivalent: "")
        viewSourceItem.target = self
        menu.addItem(viewSourceItem)
    }

    @objc private func viewSourceMenuClicked() {
        browserDelegate?.webViewDidRequestViewSource(self)
    }
    
    @objc private func savePageAsMenuClicked() {
        browserDelegate?.webViewDidRequestSavePageAs(self)
    }
    
    @objc private func copyPageTitleMenuClicked() {
        browserDelegate?.webViewDidRequestCopyPageTitle(self)
    }

    // https://stackoverflow.com/questions/46777468/swift-mac-os-blank-page-printed-when-i-try-to-print-webview-wkwebview
    @objc(print:)
    override func printView(_ sender: Any?) {
        let printInfo = NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true

        let op = printOperation(with: printInfo)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.view?.frame = bounds
        op.runModal(
          for: window!,
          delegate: self,
          didRun: nil,
          contextInfo: nil
        )
    }
    
    // MARK: - Mouse Tracking for Hover
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        clearHover()
    }
    
    func clearHover() {
        browserDelegate?.webViewDidHoverURL(self, url: nil, frame: NSZeroRect)
    }
    
}
