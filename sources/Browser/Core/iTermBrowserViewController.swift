//
//  iTermBrowserView.swift
//  iTerm2
//
//  Created by George Nachman on 6/18/25.
//

import WebKit

struct SmartSelectRule {
    var regex: String
    var weight: Double
    var actions: Array<[String: Any]>
}

@available(macOS 11.0, *)
protocol iTermBrowserViewControllerDelegate: AnyObject {
    func browserViewController(_ controller: iTermBrowserViewController,
                               didUpdateTitle title: String?)
    func browserViewController(_ controller: iTermBrowserViewController,
                               didUpdateFavicon favicon: NSImage?)
    func browserViewController(_ controller: iTermBrowserViewController,
                               requestNewWindowForURL url: URL,
                               configuration: WKWebViewConfiguration) -> WKWebView?
    func browserViewControllerShowFindPanel(_ controller: iTermBrowserViewController)
    func browserViewController(_ controller: iTermBrowserViewController,
                               openNewTabForURL url: URL)
    func browserViewController(_ controller: iTermBrowserViewController,
                               openNewSplitPaneForURL url: URL,
                               vertical: Bool)
    func browserViewController(_ controller: iTermBrowserViewController,
                               openPasswordManagerForHost host: String?,
                               forUser: Bool,
                               didSendUserName: (() -> ())?)
    func browserViewControllerDidSelectAskAI(_ controller: iTermBrowserViewController,
                                             title: String,
                                             content: String)
    func browserViewControllerSetMouseInfo(
        _ controller: iTermBrowserViewController,
        pointInView: NSPoint,
        button: Int,
        count: Int,
        modifiers: NSEvent.ModifierFlags,
        sideEffects: iTermClickSideEffects,
        state: iTermMouseState)

    func browserViewControllerMovePane(_ controller: iTermBrowserViewController)
    func browserViewControllerEnclosingTerminal(_ controller: iTermBrowserViewController) -> PseudoTerminal?
    func browserViewControllerSplit(_ controller: iTermBrowserViewController,
                                    vertically: Bool,
                                    guid: String)
    func browserViewController(_ controller: iTermBrowserViewController,
                               didHoverURL url: String?,
                               frame: NSRect)

    func browserViewControllerSelectPane(_ controller: iTermBrowserViewController,
                                         forward: Bool)
    func browserViewControllerInvoke(_ controller: iTermBrowserViewController,
                                     scriptFunction: String)
    func browserViewControllerSmartSelectionRules(
        _ controller: iTermBrowserViewController) -> [SmartSelectRule]
    func browserViewController(_ controller: iTermBrowserViewController,
                               didNavigateTo url: URL)
    func browserViewControllerDidBecomeFirstResponder(_ controller: iTermBrowserViewController)
    func browserViewController(_ controller: iTermBrowserViewController, didCopyString string: String)
    func browserViewController(_ controller: iTermBrowserViewController, runCommand command: String)
    func browserViewControllerScope(_ controller: iTermBrowserViewController) -> (iTermVariableScope, iTermObject)
    func browserViewControllerShouldInterpolateSmartSelectionParameters(_ controller: iTermBrowserViewController) -> Bool
    func browserViewController(_ controller: iTermBrowserViewController, openFile file: String)
    func browserViewController(_ controller: iTermBrowserViewController, performSplitPaneAction action: iTermBrowserSplitPaneAction)
    func browserViewControllerCurrentTabHasMultipleSessions(_ controller: iTermBrowserViewController) -> Bool
    func browserViewControllerDidStartNavigation(_ controller: iTermBrowserViewController)
    func browserViewControllerDidFinishNavigation(_ controller: iTermBrowserViewController)
    func browserViewControllerDidReceiveNamedMarkUpdate(_ controller: iTermBrowserViewController, guid: String, text: String)
}

@available(macOS 11.0, *)
@objc(iTermBrowserViewController)
class iTermBrowserViewController: NSViewController {
    weak var delegate: iTermBrowserViewControllerDelegate?
    private let browserManager: iTermBrowserManager
    private var toolbar: iTermBrowserToolbar!
    private var backgroundView: NSVisualEffectView!
    private let historyController: iTermBrowserHistoryController
    private let suggestionsController: iTermBrowserSuggestionsController
    private let navigationState = iTermBrowserNavigationState()
    @objc let sessionGuid: String
    private var bookmarkTagEditor: iTermBookmarkTagEditorWindowController?
    private lazy var contextMenuHandler = iTermBrowserContextMenuHandler(webView: browserManager.webView, parentWindow: view.window)
    private var deferredURL: String?
    private lazy var keyBindingActionPerformer =  {
        let performer = iTermBrowserKeyBindingActionPerformer()
        performer.delegate = self
        return performer
    }()
    private let pointerController = PointerController()
    private let pointerActionPerformer = iTermBrowserPointerActionPerformer()

    class ShadeView: SolidColorView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            return nil
        }
    }
    private let shadeView = ShadeView()

    @objc var zoom: CGFloat {
        get {
            round(browserManager.webView!.pageZoom * 100.0)
        }
        set {
            browserManager.webView!.pageZoom = newValue / 100.0
        }
    }
    
    deinit {
        toolbar?.cleanup()
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        toolbar?.cleanup()
    }

    @objc(initWithConfiguration:sessionGuid:profile:)
    init(configuration: WKWebViewConfiguration?, sessionGuid: String, profile: Profile)  {
        self.sessionGuid = sessionGuid
        let user: iTermBrowserUser = if iTermProfilePreferences.bool(forKey: KEY_BROWSER_DEV_NULL, inProfile: profile) {
            .devNull
        } else {
            .regular(id: UUID(uuidString: "00000000-0000-4000-8000-000000000000")!)
        }
        historyController = iTermBrowserHistoryController(user: user,
                                                          sessionGuid: sessionGuid,
                                                          navigationState: navigationState)
        browserManager = iTermBrowserManager(user: user,
                                             configuration: configuration,
                                             sessionGuid: sessionGuid,
                                             historyController: historyController,
                                             navigationState: navigationState,
                                             profile: profile,
                                             pointerController: pointerController)
        suggestionsController = iTermBrowserSuggestionsController(user: user,
                                                                  historyController: historyController,
                                                                  attributes: CompletionsWindow.regularAttributes(font: nil))
        super.init(nibName: nil, bundle: nil)

        pointerController.delegate = pointerActionPerformer
        pointerActionPerformer.delegate = self
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }
}

// MARK: -  Public API

@available(macOS 11.0, *)
extension iTermBrowserViewController {
    @objc
    func loadRestorableState(_ restorableState: NSDictionary?, orURL url: String?) {
        if let restorableState, let dict = restorableState as? [String: Any] {
            let state = iTermBrowserRestorableState.create(from: dict)
            interactionState = state.interactionState
        } else if let url {
            loadURL(url)
        }
    }

    @objc var restorableState: NSDictionary {
        let state = iTermBrowserRestorableState(interactionState: interactionState as? NSData)
        return state.dictionaryValue as NSDictionary
    }

    private var interactionState: NSObject? {
        get {
            if #available(macOS 12, *) {
                if let deferred = browserManager.webView.deferrableInteractionState {
                    return deferred as? NSData
                }
                return browserManager.webView.interactionState as? NSData
            } else {
                return nil
            }
        }
        set {
            if #available(macOS 12, *) {
                // Check if we should defer setting interaction state during restoration
                if shouldDeferLoading() {
                    browserManager.webView.deferrableInteractionState = newValue
                    return
                }

                browserManager.webView.interactionState = newValue
            }
        }
    }

    @objc override var title: String? {
        get {
            return browserManager.webView.title
        }
        set {
            super.title = newValue
        }
    }

    @objc var favicon: NSImage? {
        return browserManager.favicon
    }

    @objc var webView: WKWebView {
        return browserManager.webView
    }

    var activeSearchTerm: String? {
        if #available (macOS 13.0, *) {
            browserManager.browserFindManager?.activeSearchTerm
        } else {
            nil
        }
    }

    @objc(sendData:)
    func send(data: Data) {
        let string = data.lossyString
        guard !string.isEmpty else {
            return
        }

        Task {
            await browserManager.webView.sendText(string)
        }
    }

    @objc var dimming: CGFloat {
        get {
            shadeView.color.alphaComponent
        }
        set {
            shadeView.isHidden = newValue < 0.01
            shadeView.color = .init(white: 0.5, alpha: newValue)
        }
    }

    @objc
    func refuseFirstResponderAtCurrentMouseLocation() {
        browserManager.webView.refuseFirstResponderAtCurrentMouseLocation()
    }

    // MARK: - Search

    func startFind(_ string: String, caseSensitive: Bool) {
        if #available (macOS 13.0, *) {
            browserManager.browserFindManager?.startFind(string, caseSensitive: caseSensitive)
        }
    }

    @objc func findNext(_ sender: Any?) {
        if #available(macOS 13.0, *) {
            browserManager.browserFindManager?.findNext()
        }
    }

    @objc func findPrevious(_ sender: Any?) {
        if #available(macOS 13.0, *) {
            browserManager.browserFindManager?.findPrevious()
        }
    }

    @objc func clearFindString(_ sender: Any?) {
        if #available(macOS 13.0, *) {
            browserManager.browserFindManager?.clearFind()
        }
    }

    @objc func loadURL(_ urlString: String) {
        // Check if we should defer loading during session restoration
        if shouldDeferLoading() {
            deferredURL = urlString
            return
        }
        
        browserManager.loadURL(urlString)
    }

    // MARK: - Password

    @available(macOS 12, *)
    @objc(enterPassword:)
    func enter(password: String) {
        guard let webView = browserManager.webView else {
            return
        }
        let writer = browserManager.passwordWriter
        Task {
            try? await writer.fillPassword(webView: webView,
                                           password: password)
        }
    }

    @available(macOS 12, *)
    @objc(enterUsername:)
    func enter(username: String) {
        guard let webView = browserManager.webView else {
            return
        }
        let writer = browserManager.passwordWriter
        Task {
            try? await writer.fillUsername(webView: webView, username: username)
        }
    }

    // MARK: - Key Bindings

    /// Returns whether we handled it.
    @objc(performKeyBindingAction:event:)
    func perform(keyBindingAction action: iTermKeyBindingAction, event: NSEvent) -> Bool {
        keyBindingActionPerformer.perform(keyBindingAction: action, event: event)
    }

    // MARK: - Marks

    @objc(renameNamedMark:to:)
    func renameNamedMark(_ mark: iTermGenericNamedMarkReading, to name: String) {
        if let myMark = mark as? iTermBrowserNamedMark {
            browserManager.namedMarkManager?.rename(myMark, to: name, webView: browserManager.webView)
            NamedMarksDidChangeNotification(sessionGuid: nil).post()
        }
    }

    @objc(removeNamedMark:)
    func removeNamedMark(_ mark: iTermGenericNamedMarkReading) {
        if let myMark = mark as? iTermBrowserNamedMark {
            browserManager.namedMarkManager?.remove(myMark, webView: browserManager.webView)
            NamedMarksDidChangeNotification(sessionGuid: nil).post()
        }
    }

    @objc(namedMarks)
    var namedMarks: [iTermGenericNamedMarkReading] {
        return browserManager.namedMarkManager?.namedMarks ?? []
    }
    
    @objc(namedMarksSortedByCurrentPage)
    var namedMarksSortedByCurrentPage: [iTermGenericNamedMarkReading] {
        // If they're not loaded yet return an empty array and we'll post a
        // refresh notification when they're ready.
        return browserManager.namedMarkManager?.namedMarks ?? []
    }

    @objc(revealNamedMark:)
    func reveal(namedMark: iTermGenericNamedMarkReading) {
        if let myMark = namedMark as? iTermBrowserNamedMark {
            browserManager.namedMarkManager?.reveal(myMark, webView: browserManager.webView)
        }
    }
    
    @objc(revealNamedMarkWithGUID:)
    func revealNamedMark(guid: String) {
        if let myMark = browserManager.namedMarkManager?.namedMarks.first(where: { $0.guid == guid }) {
            browserManager.namedMarkManager?.reveal(myMark, webView: browserManager.webView)
        }
    }

    @objc
    var canAddNamedMark: Bool {
        // Check URL scheme - only allow http/https for now
        guard let currentURL = browserManager.webView.url,
              let scheme = currentURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        
        // Check HTTP method - only allow GET
        guard let httpMethod = browserManager.currentHTTPMethod else {
            return false // No method means we can't determine safety
        }
        
        return httpMethod == "GET"
    }

    // MARK: - Paste

    @objc
    func openAdvancedPaste() {
        guard let window = view.window else { return }
        Task { @MainActor [weak self] in
            let event = await iTermPasteSpecialWindowController.showAsPanel(in: window,
                                                                            chunkSize: 1_024 * 1_024,
                                                                            delayBetweenChunks: 0,
                                                                            bracketingEnabled: false,
                                                                            encoding: String.Encoding.utf8.rawValue,
                                                                            canWaitForPrompt: false,
                                                                            isAtShellPrompt: false,
                                                                            forceEscapeSymbols: false,
                                                                            shell: "",
                                                                            profileType: .browser)
            if let event {
                self?.send(data: event.string.lossyData)
            }
        }
    }
}

// MARK: -  Overrides

@available(macOS 11.0, *)
extension iTermBrowserViewController {
    override func loadView() {
        view = iTermBrowserView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupBackgroundView()
        setupBrowserManager()
        setupToolbar()
        setupWebView()
        setupShade()
        setupConstraints()
        setupRestorationObserver()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        if !shouldDeferLoading() {
            loadDeferredURLIfNeeded()
        }
    }

    @objc
    func performFindPanelAction(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem else { return }

        switch NSFindPanelAction(rawValue: UInt(menuItem.tag)) {
        case .showFindPanel:
            delegate?.browserViewControllerShowFindPanel(self)
        case .setFindString:
            // TODO: Implement setting find string from selection if needed
            break
        default:
            // Other actions are handled by the dedicated methods below
            break
        }
    }
}

// MARK: -  Setup

@available(macOS 11.0, *)
extension iTermBrowserViewController {
    private func setupBackgroundView() {
        backgroundView = NSVisualEffectView()
        backgroundView.material = .contentBackground
        backgroundView.blendingMode = .behindWindow
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backgroundView)
    }

    private func setupBrowserManager() {
        browserManager.delegate = self
    }

    private func setupToolbar() {
        toolbar = iTermBrowserToolbar()
        toolbar.delegate = self
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.setDevNullMode(browserManager.user == .devNull)
        view.addSubview(toolbar)
    }

    private func setupWebView() {
        browserManager.webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(browserManager.webView)
    }

    private func setupShade() {
        shadeView.color = .black
        shadeView.isHidden = true
        shadeView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shadeView)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Background view constraints (full view coverage)
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Toolbar constraints
            toolbar.topAnchor.constraint(equalTo: view.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 44),

            // WebView constraints
            browserManager.webView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            browserManager.webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            browserManager.webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            browserManager.webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Shadeview
            shadeView.topAnchor.constraint(equalTo: view.topAnchor),
            shadeView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            shadeView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            shadeView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }
    
    private func setupRestorationObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRestorationDidComplete),
            name: NSNotification.Name("iTermSessionRestorationDidCompleteNotification"),
            object: nil
        )
    }
    
    private func shouldDeferLoading() -> Bool {
        guard let window = view.window else {
            // No window means not in view hierarchy - definitely defer
            return true
        }
        
        // Check if delegate conforms to restoration protocol and is performing restoration
        if let restorationDelegate = window.delegate as? iTermSessionRestorationStatusProtocol {
            return restorationDelegate.isPerformingSessionRestoration
        }
        
        return false
    }
    
    @objc private func sessionRestorationDidComplete(_ notification: Notification) {
        if !shouldDeferLoading() {
            loadDeferredURLIfNeeded()
        }
    }
    
    func loadDeferredURLIfNeeded() {
        if #available(macOS 12.0, *) {
            browserManager.webView.applyDeferredInteractionStateIfNeeded()
        }

        if let url = deferredURL {
            deferredURL = nil
            browserManager.loadURL(url)
        }
    }
}

// MARK: - iTermBrowserToolbarDelegate

@available(macOS 11.0, *)
extension iTermBrowserViewController: iTermBrowserToolbarDelegate {
    func browserToolbarDidTapReload() {
        browserManager.reload()
    }

    func browserToolbarDidTapStop() {
        browserManager.stop()
    }

    func browserToolbarDidSubmitURL(_ url: String) {
        browserManager.loadURL(url)
    }

    func browserToolbarDidTapSettings() {
        browserManager.loadURL(iTermBrowserSettingsHandler.settingsURL.absoluteString)
    }

    func browserToolbarDidTapHistory() {
        browserManager.loadURL(iTermBrowserHistoryViewHandler.historyURL.absoluteString)
    }

    func browserToolbarBackHistoryItems() -> [iTermBrowserHistoryItem] {
        return browserManager.getBackHistoryItems()
    }

    func browserToolbarForwardHistoryItems() -> [iTermBrowserHistoryItem] {
        return browserManager.getForwardHistoryItems()
    }

    func browserToolbarDidSelectHistoryItem(steps: Int) {
        browserManager.navigateHistory(steps: steps)
    }

    func browserToolbarDidRequestSuggestions(_ query: String) async -> [URLSuggestion] {
        return await suggestionsController.suggestions(forQuery: query)
    }

    func browserToolbarDidBeginEditingURL(string: String) -> String? {
        return suggestionsController.searchQueryFromURL(string)
    }

    func browserToolbarUserDidSubmitNavigationRequest() {
        // When the user presses enter in the URL bar, the URL bar must lose first responder.
        browserManager.webView.window?.makeFirstResponder(browserManager.webView)
    }
    
    func browserToolbarDidTapAddBookmark() async {
        guard let currentURL = browserManager.webView.url?.absoluteString else {
            return
        }
        
        guard let database = await BrowserDatabase.instance(for: browserManager.user) else {
            return
        }
        
        let isBookmarked = await database.isBookmarked(url: currentURL)
        
        if isBookmarked {
            // Remove bookmark
            let success = await database.removeBookmark(url: currentURL)
            if success {
                ToastWindowController.showToast(withMessage: "Bookmark Removed")
            }
        } else {
            // Add bookmark first, then show tag editor
            let title = browserManager.webView.title
            let success = await database.addBookmark(url: currentURL, title: title)
            if success {
                await MainActor.run {
                    self.showBookmarkTagEditor(url: currentURL, title: title)
                }
            }
        }
    }
    
    func browserToolbarDidTapManageBookmarks() {
        browserManager.loadURL(iTermBrowserBookmarkViewHandler.bookmarksURL.absoluteString)
    }
    
    func browserToolbarDidTapReaderMode() {
        browserManager.toggleReaderMode()
    }
    
    func browserToolbarIsReaderModeActive() -> Bool {
        return browserManager.isReaderModeActive
    }
    
    func browserToolbarDidTapDistractionRemoval() {
        browserManager.toggleDistractionRemoval()
    }
    
    func browserToolbarIsDistractionRemovalActive() -> Bool {
        return browserManager.isDistractionRemovalActive
    }
    
    func browserToolbarCurrentURL() -> String? {
        return browserManager.webView.url?.absoluteString
    }
    
    func browserToolbarIsCurrentURLBookmarked() async -> Bool {
        guard let currentURL = browserManager.webView.url?.absoluteString,
              let database = await BrowserDatabase.instance(for: browserManager.user) else {
            return false
        }
        
        return await database.isBookmarked(url: currentURL)
    }

    func browserToolbarDidTapAskAI() {
        Task {
            if let pageContent = await browserManager.pageContent() {
                delegate?.browserViewControllerDidSelectAskAI(self,
                                                              title: pageContent.title,
                                                              content: pageContent.content)
            } else {
                DLog("Shouldn't be possible but no page content for \((browserManager.webView?.url).d)")
            }
        }
    }
    
    #if DEBUG
    func browserToolbarDidTapDebugAutofill() {
        browserManager.debugAutofillFields()
    }
    #endif

    func browserToolbarShouldOfferReaderMode() async -> Bool {
        return await (browserManager.pageContent()?.content ?? "").count > 10
    }
}

// MARK: - iTermBrowserManagerDelegate

@available(macOS 11.0, *)
extension iTermBrowserViewController: iTermBrowserManagerDelegate {
    func browserManager(_ manager: iTermBrowserManager, didUpdateURL url: String?) {
        // Close bookmark tag editor when navigating to a different URL
        bookmarkTagEditor?.closeFromNavigation()
        bookmarkTagEditor = nil

        toolbar.updateURL(url)
    }

    func browserManager(_ manager: iTermBrowserManager, didUpdateTitle title: String?) {
        delegate?.browserViewController(self, didUpdateTitle: title)
    }

    func browserManager(_ manager: iTermBrowserManager, didUpdateFavicon favicon: NSImage?) {
        toolbar.updateFavicon(favicon)
        delegate?.browserViewController(self, didUpdateFavicon: favicon)
    }

    func browserManager(_ manager: iTermBrowserManager, didUpdateCanGoBack canGoBack: Bool) {
        toolbar.updateNavigationButtons(canGoBack: canGoBack, canGoForward: manager.webView.canGoForward)
    }

    func browserManager(_ manager: iTermBrowserManager, didUpdateCanGoForward canGoForward: Bool) {
        toolbar.updateNavigationButtons(canGoBack: manager.webView.canGoBack, canGoForward: canGoForward)
    }

    func browserManager(_ manager: iTermBrowserManager, didStartNavigation navigation: WKNavigation?) {
        toolbar.setLoading(true)
        delegate?.browserViewControllerDidStartNavigation(self)
    }

    func browserManager(_ manager: iTermBrowserManager, didFinishNavigation navigation: WKNavigation?) {
        toolbar.setLoading(false)
        browserManager.namedMarkManager?.didFinishNavigation(webView: manager.webView, success: true)
        if let url = manager.webView.url {
            delegate?.browserViewController(self, didNavigateTo: url)
        }
        delegate?.browserViewControllerDidFinishNavigation(self)
    }

    func browserManager(_ manager: iTermBrowserManager, didFailNavigation navigation: WKNavigation?, withError error: Error) {
        toolbar.setLoading(false)
        browserManager.namedMarkManager?.didFinishNavigation(webView: manager.webView, success: false)
        delegate?.browserViewControllerDidFinishNavigation(self)
    }

    func browserManager(_ manager: iTermBrowserManager, requestNewWindowForURL url: URL, configuration: WKWebViewConfiguration) -> WKWebView? {
        return delegate?.browserViewController(self,
                                               requestNewWindowForURL: url,
                                               configuration: configuration)
    }

    func browserManager(_ manager: iTermBrowserManager, openNewTabForURL url: URL) {
        delegate?.browserViewController(self, openNewTabForURL: url)
    }

    func browserManager(_ manager: iTermBrowserManager, openNewSplitPaneForURL url: URL, vertical: Bool) {
        delegate?.browserViewController(self, openNewSplitPaneForURL: url, vertical: vertical)
    }

    func browserManager(_ manager: iTermBrowserManager,
                        openPasswordManagerForHost host: String?,
                        forUser: Bool,
                        didSendUserName: (() -> ())?) {
        delegate?.browserViewController(self,
                                        openPasswordManagerForHost: host,
                                        forUser: forUser,
                                        didSendUserName: didSendUserName)
    }

    func browserManagerDidRequestSavePageAs(_ manager: iTermBrowserManager) {
        contextMenuHandler.savePageAs()
    }

    func browserManagerDidRequestAddNamedMark(_ manager: iTermBrowserManager, atPoint point: NSPoint) {
        guard let window = browserManager.webView.window else {
            return
        }
        BookmarkDialogViewController.show(window: window) { [weak self] name in
            Task { @MainActor in
                guard let self else { return }
                try await self.browserManager.namedMarkManager?.add(with: name,
                                                    webView: self.browserManager.webView,
                                                    httpMethod: self.browserManager.currentHTTPMethod,
                                                    clickPoint: point)
                NamedMarksDidChangeNotification(sessionGuid: nil).post()
            }
        }
    }

    func browserManager(_ manager: iTermBrowserManager, didChangeReaderModeState isActive: Bool) {
        // No additional action needed - toolbar will update based on state
    }

    func browserManager(_ manager: iTermBrowserManager, didChangeDistractionRemovalState isActive: Bool) {
        // No additional action needed - toolbar will update based on state
    }

    func browserManagerSetMouseInfo(_ browserManager: iTermBrowserManager,
                                    pointInView: NSPoint,
                                    button: Int,
                                    count: Int,
                                    modifiers: NSEvent.ModifierFlags,
                                    sideEffects: iTermClickSideEffects,
                                    state: iTermMouseState) {
        delegate?.browserViewControllerSetMouseInfo(
            self,
            pointInView: pointInView,
            button: button,
            count: count,
            modifiers: modifiers,
            sideEffects: sideEffects,
            state: state)
    }

    func browserManager(_ browserManager: iTermBrowserManager, doSmartSelectionAtPointInWindow point: NSPoint) async {
        guard let rules = delegate?.browserViewControllerSmartSelectionRules(self) else {
            return
        }
        await browserManager.webView.performSmartSelection(atPointInWindow: point,
                                                           rules: rules,
                                                           requireAction: false)
    }

    func browserManager(_ browserManager: iTermBrowserManager, didHoverURL url: String?, frame: NSRect) {
        delegate?.browserViewController(self, didHoverURL: url, frame: frame)
    }

    func browserManagerDidBecomeFirstResponder(_ browserManager: iTermBrowserManager) {
        delegate?.browserViewControllerDidBecomeFirstResponder(self)
    }

    func browserManager(_ browserManager: iTermBrowserManager, didCopyString string: String) {
        delegate?.browserViewController(self, didCopyString: string)
    }

    func browserManagerSmartSelectionRules(
        _ browserManager: iTermBrowserManager) -> [SmartSelectRule] {
            return delegate?.browserViewControllerSmartSelectionRules(self) ?? []
        }
    func browserManagerRunCommand(_ browserManager: iTermBrowserManager, command: String) {
        delegate?.browserViewController(self, runCommand: command)
    }
    func browserManagerScope(_ browserManager: iTermBrowserManager) -> (iTermVariableScope, iTermObject)? {
        return delegate?.browserViewControllerScope(self)
    }
    func browserManagerShouldInterpolateSmartSelectionParameters(
        _ browserManager: iTermBrowserManager) -> Bool {
            return delegate?.browserViewControllerShouldInterpolateSmartSelectionParameters(self) ?? false
        }
    func browserManager(_ browserManager: iTermBrowserManager, openFile file: String) {
        delegate?.browserViewController(self, openFile: file)
    }
    func browserManager(_ browserManager: iTermBrowserManager, performSplitPaneAction action: iTermBrowserSplitPaneAction) {
        delegate?.browserViewController(self, performSplitPaneAction: action)
    }
    func browserManagerCurrentTabHasMultipleSessions(_ browserManager: iTermBrowserManager) -> Bool {
        return delegate?.browserViewControllerCurrentTabHasMultipleSessions(self) ?? false
    }
    
    func browserManager(_ manager: iTermBrowserManager, didReceiveNamedMarkUpdate guid: String, text: String) {
        delegate?.browserViewControllerDidReceiveNamedMarkUpdate(self, guid: guid, text: text)
    }
}

// MARK: - Actions

@available(macOS 11.0, *)
extension iTermBrowserViewController {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(addNamedMark(_:)) {
            return canAddNamedMark
        }
        return true
    }

    @objc(pasteOptions:)
    func pasteOptions(_ sender: Any) {
        openAdvancedPaste()
    }

    @objc
    @IBAction
    func browserOpenLocation(_ sender: Any) {
        toolbar.focusURLBar()
    }

    @objc
    @IBAction
    func browserBack(_ sender: Any) {
        toolbar.backTapped()
    }

    @objc
    @IBAction
    func browserForward(_ sender: Any) {
        toolbar.forwardTapped()
    }

    @objc
    @IBAction
    func browserReload(_ sender: Any) {
        toolbar.reloadTapped()
    }

    @objc
    @IBAction
    func browserHistory(_ sender: Any) {
        browserManager.loadURL(iTermBrowserHistoryViewHandler.historyURL.absoluteString)
    }

    @objc(addNamedMark:)
    func addNamedMark(_ sender: Any) {
        guard let window = browserManager.webView.window else {
            return
        }
        BookmarkDialogViewController.show(window: window) { [weak self] name in
            Task { @MainActor in
                guard let self else { return }
                try await self.browserManager.namedMarkManager?.add(with: name,
                                                    webView: self.browserManager.webView,
                                                    httpMethod: self.browserManager.currentHTTPMethod)
                NamedMarksDidChangeNotification(sessionGuid: nil).post()
            }
        }
    }

}

// MARK: - Bookmark Management

@available(macOS 11.0, *)
extension iTermBrowserViewController: iTermBookmarkTagEditorDelegate {
    private func showBookmarkTagEditor(url: String, title: String?) {
        // Close existing editor if open
        bookmarkTagEditor?.close()
        
        // Create and show new editor
        let editor = iTermBookmarkTagEditorWindowController(user: browserManager.user,
                                                            url: url,
                                                            title: title,
                                                            delegate: self)
        bookmarkTagEditor = editor
        editor.showWindow(self)
        
        // Position relative to browser window
        if let browserWindow = view.window,
           let editorWindow = editor.window {
            let browserFrame = browserWindow.frame
            let editorSize = editorWindow.frame.size
            let x = browserFrame.midX - editorSize.width / 2
            let y = browserFrame.midY - editorSize.height / 2
            editorWindow.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
    
    // MARK: - iTermBookmarkTagEditorDelegate
    
    func bookmarkTagEditorWillClose(_ controller: iTermBookmarkTagEditorWindowController) {
        bookmarkTagEditor = nil
    }
}

@available(macOS 11.0, *)
@objc(iTermBrowserView)
class iTermBrowserView: NSView {
}

@available(macOS 11.0, *)
extension iTermBrowserViewController: iTermBrowserActionPerforming {
    func actionPerformExtendSelection(toPointInWindow point: NSPoint) {
        browserManager.webView.extendSelection(toPointInWindow: point)
    }

    func actionPerformingOpen(atWindowLocation point: NSPoint,
                              inBackground: Bool) {
        browserManager.webView.openLink(atPointInWindow: point, inNewTab: inBackground)
    }

    func actionPerformingSmartSelect(atWindowLocation point: NSPoint) {
        guard let rules = delegate?.browserViewControllerSmartSelectionRules(self) else {
            return
        }
        Task {
            await browserManager.webView.performSmartSelection(atPointInWindow: point,
                                                               rules: rules,
                                                               requireAction: false)
        }
    }

    func actionPerformingOpenContextMenu(atWindowLocation point: NSPoint) {
        guard let webView = browserManager.webView else {
            return
        }
        webView.openContextMenu(atPointInWindow: point,
                                allowJavascriptToIntercept: true)
    }

    func actionPerformingMovePane() {
        delegate?.browserViewControllerMovePane(self)
    }

    func actionPerformingCurrentTerminal() -> PseudoTerminal? {
        return delegate?.browserViewControllerEnclosingTerminal(self)
    }

    func actionPerformingSplit(vertically: Bool, guid: String) {
        delegate?.browserViewControllerSplit(self, vertically: vertically, guid: guid)
    }

    func actionPerformingSelectPane(forward: Bool) {
        delegate?.browserViewControllerSelectPane(self, forward: forward)
    }

    func actionPerformingInvoke(scriptFunction: String) {
        delegate?.browserViewControllerInvoke(self, scriptFunction: scriptFunction)
    }

    func actionPerformingScroll(movement: ScrollMovement) {
        browserManager.webView.performScroll(movement: movement)
    }

    func actionPerformingSend(data: Data, broadcastAllowed: Bool) {
        guard let string = String(data: data, encoding: .utf8) else { return }

        Task {
            await browserManager.webView.sendText(string)
        }
    }

    func actionPerformingExtendSelect(start: Bool, forward: Bool, by: PTYTextViewSelectionExtensionUnit) {
        browserManager.webView.extendSelection(start: start, forward: forward, by: by)
    }

    func actionPerformingHasSelection() async -> Bool {
        return await browserManager.webView.hasSelection()
    }

    func actionPerformingCopyToClipboard() {
        NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: browserManager.webView)
    }

    func actionPerformingPasteFromClipboard() {
        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: browserManager.webView)
    }

    func actionPerformingOpenQuickLook(atPointInWindow point: NSPoint) {
        guard let window = view.window else {
            return
        }
        
        Task {
            let webUrls = await browserManager.webView.urls(atPointInWindow: point)
            guard !webUrls.isEmpty else {
                return
            }
            
            let screenRect = window.convertToScreen(NSRect(origin: point, size: NSSize(width: 1, height: 1)))
            let helper = QuickLookHelper()
            helper.showQuickLookWithDownloads(for: webUrls, from: screenRect)
        }
    }

    func actionPerformingPasteSpecial(config: String, fromSelection: Bool) {
        Task { @MainActor in
            let string: String?
            if fromSelection {
                string = await browserManager.webView.selectedText
            } else {
                string = NSString.fromPasteboard()
            }
            if let string {
                let event = iTermPasteSpecialViewController.pasteEvent(forConfig: config, string: string)
                iTermPasteHelper.sanitizePasteEvent(event, encoding: String.Encoding.utf8.rawValue)
                if let data = event?.string.lossyData {
                    send(data: data)
                }
            }
        }
    }
}

