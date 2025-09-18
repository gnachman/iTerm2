//
//  iTermBrowserWebView.swift
//  iTerm2
//
//  Created by George Nachman on 6/19/25.
//

import WebKit

@available(macOS 11.0, *)
@MainActor
protocol iTermBrowserWebViewDelegate: AnyObject {
    func webViewDidRequestViewSource(_ webView: iTermBrowserWebView)
    func webViewDidRequestSavePageAs(_ webView: iTermBrowserWebView)
    func webViewDidRequestAddNamedMark(_ webView: iTermBrowserWebView, atPoint point: NSPoint)

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
    func webViewDidRequestRemoveElement(_ webView: iTermBrowserWebView, at: NSPoint)
    func webViewDidBecomeFirstResponder(_ webView: iTermBrowserWebView)
    func webViewDidCopy(_ webView: iTermBrowserWebView, string: String)
    func webViewSearchEngineName(_ webView: iTermBrowserWebView) -> String?
    func webViewPerformWebSearch(_ webView: iTermBrowserWebView, query: String)
    func webViewSmartSelectionRules(_ webView: iTermBrowserWebView) -> [SmartSelectRule]
    func webViewRunCommand(_ webView: iTermBrowserWebView, command: String)
    func webViewScope(_ webView: iTermBrowserWebView) -> (iTermVariableScope, iTermObject)?
    func webViewScopeShouldInterpolateSmartSelectionParameters(_ webView: iTermBrowserWebView) -> Bool
    func webViewOpenFile(_ webView: iTermBrowserWebView, file: String)
    func webViewPerformSplitPaneAction(_ webView: iTermBrowserWebView, action: iTermBrowserSplitPaneAction)
    func webViewCurrentTabHasMultipleSessions(_ webView: iTermBrowserWebView) -> Bool
    func webView(_ webView: iTermBrowserWebView, didReceiveEvent: iTermBrowserWebView.Event)
    func webView(_ webView: iTermBrowserWebView, handleKeyDown event: NSEvent) -> Bool
    func webViewDidChangeEffectiveAppearance(_ webView: iTermBrowserWebView)
}

@MainActor
@objc
protocol iTermEditableTextDetecting {
    var isEditingText: Bool { get }
}

@available(macOS 11.0, *)
@MainActor
class iTermBrowserWebView: iTermBaseWKWebView, iTermEditableTextDetecting {
    enum Event {
        case insert(text: String)
        case doCommandBySelector(Selector?)
    }

    weak var browserDelegate: iTermBrowserWebViewDelegate?
    var deferrableInteractionState: Any?
    private let pointerController: PointerController
    private var threeFingerTapGestureRecognizer: ThreeFingerTapGestureRecognizer!
    private var mouseDownIsThreeFingerClick = false  // TODO
    private var numTouches = 0  // TODO
    private var mouseDown = false  // TODO
    private var mouseDownLocationInWindow: NSPoint?
    private var hoverLinkSecret: String?
    private var trackingArea: NSTrackingArea?
    private let focusFollowsMouse = iTermFocusFollowsMouse()
    private let contextMenuHelper = iTermBrowserContextMenuHelper()
    var receivingBroadcast = false
    @objc var isEditingText = false

    var currentSelection: String? {
        didSet {
            DLog("current selection changed to \(currentSelection.d)")
            if iTermPreferences.bool(forKey: kPreferenceKeySelectionCopiesText),
               let selection = currentSelection,
               !selection.isEmpty {
                copy(string: selection)
            }
        }
    }

    init(frame: CGRect,
         configuration: WKWebViewConfiguration,
         pointerController: PointerController) {
        self.pointerController = pointerController

        super.init(frame: frame, configuration: configuration)
        if #available(macOS 13.3, *) {
            isInspectable = true
        }
        contextMenuHelper.delegate = self
        focusFollowsMouse.delegate = self
        allowsMagnification = true
        threeFingerTapGestureRecognizer = ThreeFingerTapGestureRecognizer(target: self,
                                                                          selector: #selector(threeFingerTap(_:)))
        allowedTouchTypes = .indirect
        wantsRestingTouches = true

        // Set up tracking area for mouse enter/exit
        updateTrackingAreas()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidResignActive(_:)),
                                               name: NSApplication.didResignActiveNotification,
                                               object: nil)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    deinit {
        threeFingerTapGestureRecognizer.disconnectTarget()
    }

    @MainActor public func safelyCallAsyncJavaScript(_ functionBody: String,
                                                     arguments: [String : Any] = [:],
                                                     in frame: WKFrameInfo? = nil,
                                                     contentWorld: WKContentWorld) async throws -> Any? {
        return try await callAsyncJavaScript(functionBody,
                                             arguments: arguments,
                                             in: frame,
                                             contentWorld: contentWorld)
    }

    // On some mapsmcOS versions evaluateJavascript crashes if undefined is returned. <3
    private func makeSafe(_ script: String) -> String {
        """
        (() => {
            let __result__ = (function() {
                return \(script)
            })();
            return typeof __result__ === 'undefined' ? null : __result__;
        })()
        """
    }

    @MainActor func safelyEvaluateJavaScript(_ unsafeScript: String,
                                             in frame: WKFrameInfo? = nil) async throws -> Any? {
        return try await safelyEvaluateJavaScript(unsafeScript, in: nil, contentWorld: .page)
    }

    @MainActor func safelyEvaluateJavaScript(_ javaScript: String,
                                             in frame: WKFrameInfo? = nil,
                                             in contentWorld: WKContentWorld,
                                             completionHandler: (@MainActor @Sendable (Result<Any?, any Error>) -> Void)? = nil) {
        Task { @MainActor in
            do {
                let result = try await safelyEvaluateJavaScript(javaScript, in: frame, contentWorld: contentWorld)
                completionHandler?(.success(result))
            } catch {
                completionHandler?(.failure(error))
            }
        }
    }


    @MainActor func safelyEvaluateJavaScript(_ unsafeScript: String,
                                             in frame: WKFrameInfo? = nil,
                                             contentWorld: WKContentWorld) async throws -> Any? {
        let javaScript = makeSafe(unsafeScript)
        do {
            let result = try await evaluateJavaScript(javaScript, in: frame, contentWorld: contentWorld)
            return result
        } catch {
            throw error
        }
    }

    // Convenience methods with completion handlers for easier migration
    @MainActor func safelyEvaluateJavaScript(_ javaScript: String,
                                             contentWorld: WKContentWorld,
                                             completionHandler: ((Any?, Error?) -> Void)? = nil) {
        Task { @MainActor in
            do {
                let result = try await safelyEvaluateJavaScript(javaScript, contentWorld: contentWorld)
                completionHandler?(result, nil)
            } catch {
                completionHandler?(nil, error)
            }
        }
    }

    @MainActor func safelyCallAsyncJavaScript(_ functionBody: String,
                                              arguments: [String : Any] = [:],
                                              contentWorld: WKContentWorld,
                                              completionHandler: ((Any?, Error?) -> Void)? = nil) {
        Task { @MainActor in
            do {
                let result = try await safelyCallAsyncJavaScript(functionBody, arguments: arguments, contentWorld: contentWorld)
                completionHandler?(result, nil)
            } catch {
                completionHandler?(nil, error)
            }
        }
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

    func openContextMenu(atJavascriptLocation jsPoint: NSPoint) {
        let pointInWindow = convertFromJavascriptCoordinates(jsPoint)
        openContextMenu(atPointInWindow: pointInWindow, allowJavascriptToIntercept: false)
    }

    func openContextMenu(atPointInWindow point: NSPoint,
                         allowJavascriptToIntercept: Bool) {
        DLog("open context menu")
        guard let window else {
            return
        }
        Task { @MainActor in
            DLog("fetching selection")
            currentSelection = try? await safelyEvaluateJavaScript(iife("return window.getSelection().toString();"),
                                                                   contentWorld: .page) as? String
            DLog("selection is \(currentSelection.d)")
            // For the event location, we might need to use the original window coordinates
            // since the menu positioning could be relative to the window
            let windowNumber = window.windowNumber
            let timestamp = ProcessInfo.processInfo.systemUptime

            // This works in conjunction with iTermBrowserContextMenuMonitor, which only allows the
            // context menu to go through if option is pressed. That way we know the selection before
            // it opens.
            guard let rightMouseDown = NSEvent.mouseEvent(with: .rightMouseDown,
                                                          location: point,
                                                          modifierFlags: allowJavascriptToIntercept ? [] : [.option],
                                                          timestamp: timestamp,
                                                          windowNumber: windowNumber,
                                                          context: nil,
                                                          eventNumber: 1,
                                                          clickCount: 1,
                                                          pressure: 1.0) else {
                DLog("Failed to create right mouse down event")
                return
            }

            // Create corresponding right mouse up event
            guard let rightMouseUp = NSEvent.mouseEvent(with: .rightMouseUp,
                                                        location: point,
                                                        modifierFlags: allowJavascriptToIntercept ? [] : [.option],
                                                        timestamp: timestamp + 0.1,
                                                        windowNumber: windowNumber,
                                                        context: nil,
                                                        eventNumber: 2,
                                                        clickCount: 1,
                                                        pressure: 1.0) else {
                DLog("Failed to create right mouse up event")
                return
            }

            DLog("Sending right mouse events to webView")

            // Send the events directly to the web view
            self.rightMouseDown(with: rightMouseDown)
            self.rightMouseUp(with: rightMouseUp)
        }
    }

    // MARK: - NSView

    override func viewDidChangeEffectiveAppearance() {
        browserDelegate?.webViewDidChangeEffectiveAppearance(self)
    }

    override func keyDown(with event: NSEvent) {
        if browserDelegate?.webView(self, handleKeyDown: event) == true {
            return
        }
        super.keyDown(with: event)
    }

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
        } else {
            DLog("Not calling super")
        }
        if sideEffects != [.ignore] {
            setMouseInfo(event: event, sideEffects: sideEffects)
        }
    }

    override var description: String {
        "<\(NSStringFromClass(Self.self)): \(it_addressString) url=\(url.d)>)"
    }
    override var acceptsFirstResponder: Bool {
        DLog("acceptsFirstResponder \(url.d)")
        return true
    }

    override func becomeFirstResponder() -> Bool {
        DLog("becomeFirstResponder \(url.d)")
        browserDelegate?.webViewDidBecomeFirstResponder(self)
        return true
    }

    override func resignFirstResponder() -> Bool {
        DLog("Resign first responder \(url.d)")
        return true
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
            // Unfortunately this breaks double-click followed by drag. Better to keep that working than have smart select on double click.
            // 2
            4
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
        Task { @MainActor in
            DLog("fetching selection")
            currentSelection = try? await safelyEvaluateJavaScript(iife("return window.getSelection().toString();"),
                                                                   contentWorld: .page) as? String
        }
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
        } else if event.clickCount == 1,
                  event.modifierFlags.intersection([.control, .command, .option, .shift]) == [.command],
                  let rules = browserDelegate?.webViewSmartSelectionRules(self) {
            Task {
                if let match = await performSmartSelection(atPointInWindow: event.locationInWindow, rules: rules, requireAction: true),
                   let actionDict = match.rule.actions.first,
                   let interpolate = browserDelegate?.webViewScopeShouldInterpolateSmartSelectionParameters(self) {
                    DLog("Construct payload with components: \(match.components)")
                    let payload = SmartSelectionActionPayload(actionDict: actionDict,
                                                              captureComponents: match.components,
                                                              useInterpolation: interpolate)
                    performSmartSelectionAction(payload: payload)
                }
            }
        }
        mouseDown = false

        super.mouseUp(with: event)
        setMouseInfo(event: event, sideEffects: [])

        return []
    }

    private func performSmartSelectionAction(payload: SmartSelectionActionPayload) {
        evaluateCustomAction(payload: payload) { [weak self] string in
            guard let string else {
                return
            }
            self?.executeSmartSelectionAction(payload: payload, evaluatedString: string)
        }
    }

    private func executeSmartSelectionAction(payload: SmartSelectionActionPayload,
                                             evaluatedString string: String) {
        let actionEnum = ContextMenuActionPrefsController.action(forActionDict: payload.actionDict)
        switch actionEnum {
        case .openFileContextMenuAction:
            browserDelegate?.webViewOpenFile(self, file: string)
        case .openUrlContextMenuAction:
            if let url = URL(string: string) {
                browserDelegate?.webViewOpenURLInNewTab(self, url: url)
            }
        case .runCommandContextMenuAction, .runCoprocessContextMenuAction, .sendTextContextMenuAction:
            //  Nots upported
            break
        case .runCommandInWindowContextMenuAction:
            browserDelegate?.webViewRunCommand(self, command: string)
        case .copyContextMenuAction:
            copy(string: string)

        @unknown default:
            break
        }
    }

    fileprivate func evaluateCustomAction(payload: SmartSelectionActionPayload,
                                          completion: @escaping (String?) -> ()) {
        guard let tuple = browserDelegate?.webViewScope(self),
              let myScope = tuple.0.copy() as? iTermVariableScope else {
            return
        }
        // You can define local values with:
        // myScope.setValue(vlaue, forVariableNamed:key)
        // But we should just define the relevant things like URL for all web pgaes.
        ContextMenuActionPrefsController.computeParameter(
            forActionDict: payload.actionDict,
            withCaptureComponents: payload.captureComponents,
            useInterpolation: payload.useInterpolation,
            scope: myScope,
            owner: tuple.1,
            completion: completion)
    }

    override func rightMouseUp(with event: NSEvent) {
        DLog("rightMouseUp")
        if threeFingerTapGestureRecognizer.rightMouseUp(event) {
            return
        }
        if pointerController.mouseUp(event, withTouches: Int32(numTouches), reportable: false) {
            setMouseInfo(event: event, sideEffects: [.performBoundAction])
            return
        }
        DLog("super.rightMouseUp")
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
        }
        super.mouseDragged(with: event)
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

    @objc override func printView(_ sender: Any?) {
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

    // MARK: - Notifications

    @objc private func applicationDidResignActive(_ notification: Notification) {
        numTouches = 0
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
        DLog("will open menu")
        contextMenuHelper.decorate(menu: menu, event: event)
    }

    // MARK: - Mouse Tracking for Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        // Remove existing tracking area if present
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }

        // Create new tracking area for mouse enter/exit
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow]
        if focusFollowsMouse.focusFollowsMouse {
            options.insert(.mouseMoved)
        }
        trackingArea = NSTrackingArea(rect: bounds,
                                      options: options,
                                      owner: self,
                                      userInfo: nil)

        if let trackingArea = trackingArea {
            addTrackingArea(trackingArea)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        _ = focusFollowsMouse.mouseWillEnter(with: event)
        focusFollowsMouse.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        _ = focusFollowsMouse.mouseExited(with: event)
        clearHover()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        focusFollowsMouse.mouseMoved(with: event)
    }
    func clearHover() {
        browserDelegate?.webViewDidHoverURL(self, url: nil, frame: NSZeroRect)
    }

}

@available(macOS 11.0, *)
@MainActor
extension iTermBrowserWebView: iTermFocusFollowsMouseDelegate {
    func focusFollowsMouseDidBecomeFirstResponder() {
        browserDelegate?.webViewDidBecomeFirstResponder(self)
    }

    func focusFollowsMouseDesiredFirstResponder() -> NSResponder {
        return self
    }

    func focusFollowsMouseDidChangeMouseLocationToRefusFirstResponderAt() {
    }
}

@MainActor
extension iTermBrowserWebView {
    func refuseFirstResponderAtCurrentMouseLocation() {
        focusFollowsMouse.refuseFirstResponderAtCurrentMouseLocation()
    }
}

@available(macOS 11.0, *)
@MainActor
extension iTermBrowserWebView: iTermBrowserContextMenuHelperDelegate {
    func contextMenuCurrentSelection() -> String? {
        return currentSelection
    }

    func contextMenuAddNamedMark(at point: NSPoint) {
        browserDelegate?.webViewDidRequestAddNamedMark(
            self,
            atPoint: convertToJavaScriptCoordinates(point))
    }

    func contextMenuConvertPointFromWindowToView(_ point: NSPoint) -> NSPoint {
        return convert(point, to: nil)
    }

    func contextMenuViewSource() {
        browserDelegate?.webViewDidRequestViewSource(self)
    }

    func contextMenuSavePageAs() {
        browserDelegate?.webViewDidRequestSavePageAs(self)
    }

    func contextMenuCopyPageTitle() {
        var string = title
        if (string ?? "").isEmpty {
            string = url?.absoluteString ?? ""
        }
        if let string, !string.isEmpty {
            copy(string: string)
        }
    }

    func contextMenuPrint() {
        printView(nil)
    }

    func contextMenuRemoveElement(at point: NSPoint) {
        browserDelegate?.webViewDidRequestRemoveElement(
            self,
            at: convertToJavaScriptCoordinates(point))
    }

    func contextMenuCopy(string: String) {
        copy(string: string)
    }

    func contextMenuCopy(data: Data) {
        copy(string: data.lossyString)
    }

    func contextMenuSearchEngineName() -> String? {
        return browserDelegate?.webViewSearchEngineName(self)
    }

    func contextMenuSearch(for query: String) {
        browserDelegate?.webViewPerformWebSearch(self, query: query)
    }

    func contextMenuSmartSelectionMatches(forText text: String) -> [WebSmartMatch] {
        guard let rules = (browserDelegate?.webViewSmartSelectionRules(self)) else {
            return []
        }
        return allMatches(rules: rules, in: text)
    }

    func contextMenuCurrentURL() -> URL? {
        return url
    }

    func contextMenuOpenFile(_ value: String) {
        browserDelegate?.webViewOpenFile(self, file: value)
    }

    func contextMenuOpenURL(_ value: String) {
        if let url = URL(string: value) {
            browserDelegate?.webViewOpenURLInNewTab(self, url: url)
        }
    }

    func contextMenuRunCommand(_ value: String) {
        browserDelegate?.webViewRunCommand(self, command: value)
    }

    func contextMenuScope() -> (iTermVariableScope, iTermObject)? {
        return browserDelegate?.webViewScope(self)
    }

    func contextMenuPerformSmartSelectionAction(payload: SmartSelectionActionPayload) {
        performSmartSelectionAction(payload: payload)
    }

    func contextMenuInterpolateSmartSelectionParameters() -> Bool {
        return browserDelegate?.webViewScopeShouldInterpolateSmartSelectionParameters(self) ?? false
    }

    func contextMenuPerformSplitPaneAction(action: iTermBrowserSplitPaneAction) {
        browserDelegate?.webViewPerformSplitPaneAction(self, action: action)
    }

    func contextMenuCurrentTabHasMultipleSessions() -> Bool {
        return browserDelegate?.webViewCurrentTabHasMultipleSessions(self) ?? false
    }
}

// MARK: - Internal methods

@available(macOS 11.0, *)
@MainActor
extension iTermBrowserWebView {
    func copy(string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        browserDelegate?.webViewDidCopy(self, string: string)
    }

    var selectedText: String? {
        get async {
            let script = """
            (function() {
                var selection = window.getSelection();
                return selection ? selection.toString() : "";
            })();
            """
            do {
                let result = try await safelyEvaluateJavaScript(script, contentWorld: .page)
                return result as? String
            } catch {
                DLog("\(error)")
                return nil
            }
        }
    }
}

extension iTermBrowserWebView {
    @objc(insertText:replacementRange:)
    override func insertText(_ insertString: Any!, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
        if !receivingBroadcast {
            browserDelegate?.webView(self, didReceiveEvent: .insert(text: "\(insertString!)"))
        }
    }

    @objc(doCommandBySelector:)
    override func doCommand(by selector: Selector!) {
        super.doCommand(by: selector)
        if !receivingBroadcast {
            browserDelegate?.webView(self, didReceiveEvent: .doCommandBySelector(selector))
        }
    }
}


// safelyEvaluateJavaScript expects an IIFE. This makes it prettier to wrap a blob of code.
func iife(_ value: String) -> String {
    return "(function() {" + value + "})();"
}
