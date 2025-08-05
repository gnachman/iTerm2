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

@MainActor
protocol iTermBrowserViewControllerDelegate: AnyObject, iTermBrowserFindManagerDelegate {
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
    func browserViewControllerBroadcastWebViews(_ controller: iTermBrowserViewController) -> [iTermBrowserWebView]
    func browserViewController(_ controller: iTermBrowserViewController,
                               showError: String,
                               suppressionKey: String,
                               identifier: String)
    func browserViewControllerBury(_ controller: iTermBrowserViewController)
    func browserViewController<T>(_ controller: iTermBrowserViewController,
                                  announce: BrowserAnnouncement<T>) async -> T?
    func browserViewController(_ controller: iTermBrowserViewController,
                               handleKeyDown event: NSEvent) -> Bool
}

@MainActor
@objc(iTermBrowserViewController)
class iTermBrowserViewController: NSViewController {
    private let browserManager: iTermBrowserManager
    private var toolbar: iTermBrowserToolbar!
    private var backgroundView: NSVisualEffectView!
    private let historyController: iTermBrowserHistoryController
    private let suggestionsController: iTermBrowserSuggestionsController
    private let navigationState = iTermBrowserNavigationState()
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
    private static let didDeinitialize = Notification.Name("iTermBrowserViewControllerDidDeinitialize")
    private let logger = iTermLogger()
    private let shadeView = ShadeView()
    private var instantReplayMovieBuilder: InstantReplayMovieBuilder?
    private var videoWindowController: VideoPlaybackWindowController?
    private let profileObserver: iTermProfilePreferenceObserver
    private let indicatorsHelper: iTermIndicatorsHelper

    // API
    weak var delegate: iTermBrowserViewControllerDelegate?
    @objc let sessionGuid: String
    @objc var copyMode: Bool {
        get {
            browserManager.copyModeHandler?.enabled ?? false
        }
        set {
            browserManager.copyModeHandler?.enabled = newValue
        }
    }

    class ShadeView: SolidColorView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            return nil
        }
    }

    @objc var zoom: CGFloat {
        get {
            round(browserManager.webView!.pageZoom * 100.0)
        }
        set {
            browserManager.webView!.pageZoom = newValue / 100.0
        }
    }
    
    deinit {
        if let toolbar {
            DispatchQueue.main.async {
                toolbar.cleanup()
            }
        }
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        toolbar?.cleanup()
    }

    init(configuration: WKWebViewConfiguration?,
         sessionGuid: String,
         profileObserver: iTermProfilePreferenceObserver,
         profileMutator: iTermProfilePreferenceMutator,
         indicatorsHelper: iTermIndicatorsHelper)  {
        self.sessionGuid = sessionGuid
        self.profileObserver = profileObserver
        self.indicatorsHelper = indicatorsHelper
        let user: iTermBrowserUser = if profileObserver.value(KEY_BROWSER_DEV_NULL) == true {
            .devNull
        } else {
            .regular(id: UUID(uuidString: "AC0E9812-7F88-478B-B361-5526082EDDB3")!)
        }
        historyController = iTermBrowserHistoryController(user: user,
                                                          sessionGuid: sessionGuid,
                                                          navigationState: navigationState)
        browserManager = iTermBrowserManager(user: user,
                                             configuration: configuration,
                                             sessionGuid: sessionGuid,
                                             historyController: historyController,
                                             navigationState: navigationState,
                                             profileObserver: profileObserver,
                                             profileMutator: profileMutator,
                                             pointerController: pointerController)
        suggestionsController = iTermBrowserSuggestionsController(user: user,
                                                                  historyController: historyController,
                                                                  attributes: CompletionsWindow.regularAttributes(font: nil))
        super.init(nibName: nil, bundle: nil)

        pointerController.delegate = pointerActionPerformer
        pointerActionPerformer.delegate = self
        browserManager.copyModeHandler?.delegate = self
        updateInstantReplayEnabled()
        profileObserver.observeBool(key: KEY_INSTANT_REPLAY) { [weak self] _, _ in
            self?.updateInstantReplayEnabled()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(otherBrowserViewControllerDidDeinitialize),
            name: Self.didDeinitialize,
            object: nil)

        indicatorsHelper.configurationObserver = { [weak self] in
            self?.toolbar.checkIndicatorsForUpdate()
        }
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }
}

// MARK: -  Public API

@MainActor
extension iTermBrowserViewController {
    @objc
    func findPanelDidHide() {
        browserManager.browserFindManager?.clearFind()
    }

    @objc
    func openAutocomplete() {
        Task {
            await browserManager.autofillHandler?.fillAll(webView: browserManager.webView)
        }
    }
    @objc
    var instantReplayAvailable: Bool {
        return instantReplayMovieBuilder != nil
    }

    @objc
    func startInstantReplay() {
        Task {
            if let instantReplayMovieBuilder {
                videoWindowController = VideoPlaybackWindowController(videoSize: instantReplayMovieBuilder.expectedSize())
                videoWindowController?.window?.makeKeyAndOrderFront(nil)
                do {
                    let (url, _) = try await instantReplayMovieBuilder.save()
                    videoWindowController?.setVideoURL(url)
                } catch {
                    videoWindowController?.close()
                    videoWindowController = nil
                    iTermWarning.show(withTitle: "Could not create movie: \(error.localizedDescription)",
                                      actions: ["OK"],
                                      accessory: nil,
                                      identifier: nil,
                                      silenceable: .kiTermWarningTypePersistent,
                                      heading: "Problem saving instant replay movie",
                                      window: view.window)
                }
            }
        }
    }
    @objc
    var hasSelection: Bool {
        return !(browserManager.webView?.currentSelection?.isEmpty ?? true)
    }

    @objc
    func jumpToSelection() {
        browserManager.webView?.evaluateJavaScript("""
        (function() {
          try {
            const sel = window.getSelection();
            if (sel.rangeCount === 0) return;
            const rect = sel.getRangeAt(0).getBoundingClientRect();
            window.scrollTo({
              top: window.scrollY + rect.top - window.innerHeight/2,
              behavior: 'smooth'
            });
          } catch (e) {
            console.error(e);
          }
        })();
        """)
    }

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

    private func updateInstantReplayEnabled() {
        if profileObserver.value(KEY_INSTANT_REPLAY) == true {
            instantReplayMovieBuilder = InstantReplayMovieBuilder(
                view: browserManager.webView,
                maxMemoryMB: iTermPreferences.integer(forKey: kPreferenceKeyInstantReplayMemoryMegabytes),
                bitsPerPixel: 0.02,
                profile: .medium)
        } else {
            instantReplayMovieBuilder?.stop()
            instantReplayMovieBuilder = nil
        }
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

    @objc var webView: iTermBrowserWebView {
        return browserManager.webView
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

    @objc(performDeferredInitializationInWindow:)
    func performDeferredInitialization(window: NSWindow) {
        if let restorationDelegate = window.delegate as? iTermSessionRestorationStatusProtocol,
           restorationDelegate.isPerformingSessionRestoration {
            DLog("Not doing global search on \(self) becaue session restoration is underway")
            return
        }
        loadDeferredURLIfNeeded()
    }

    @objc(executeGlobalSearch:mode:)
    func executeGlobalSearch(query: String, mode: iTermFindMode) -> iTermBrowserGlobalSearchResultStream? {
        return browserManager.browserFindManager?.executeGlobalSearch(
            query: query,
            mode: mode.browserFindMode(query: query))
    }

    @objc(revealFindResult:completion:)
    func reveal(findResult: iTermBrowserFindResult,
                completion: @escaping @MainActor (NSRect) -> ()) {
        guard let findManager = browserManager.browserFindManager,
              let matchIdentifier = findResult.matchIdentifier else {
            completion(.zero)
            return
        }
        Task {
            do {
                let jsrect = try await findManager.reveal(
                    globalFindResultWithIdentifier: matchIdentifier)
                let windowOrigin = browserManager.webView.convertFromJavascriptCoordinates(jsrect.minXmaxY)
                let windowOpposite = browserManager.webView.convertFromJavascriptCoordinates(jsrect.maxXminY)
                let rect = NSRect(origin: windowOrigin, size: abs(windowOpposite - windowOrigin))
                if let screenRect = view.window?.convertToScreen(rect) {
                    completion(screenRect)
                } else {
                    DLog("No window")
                    completion(.zero)
                }
            } catch {
                DLog("\(error)")
                completion(.zero)
            }
        }
    }

    func startFind(_ string: String, mode: iTermBrowserFindMode, force: Bool) {
        browserManager.browserFindManager?.startFind(string, mode: mode, force: force)
    }

    @objc(bury:)
    func bury(_ sender: Any?) {
        delegate?.browserViewControllerBury(self)
    }

    @objc func findNext(_ sender: Any?) {
        browserManager.browserFindManager?.findNext()
    }

    @objc func findPrevious(_ sender: Any?) {
        browserManager.browserFindManager?.findPrevious()
    }

    @objc func clearFindString(_ sender: Any?) {
        browserManager.browserFindManager?.clearFind()
    }
    
    // Additional find methods for integration with iTerm2's find system
    
    var activeSearchTerm: String? {
        return browserManager.browserFindManager?.activeSearchTerm
    }
    
    var hasActiveSearch: Bool {
        return browserManager.browserFindManager?.hasActiveSearch ?? false
    }
    
    var numberOfSearchResults: Int {
        return browserManager.browserFindManager?.numberOfSearchResults ?? 0
    }
    
    var currentIndex: Int {
        return browserManager.browserFindManager?.currentIndex ?? 0
    }
    
    var findInProgress: Bool {
        return browserManager.browserFindManager?.findInProgress ?? false
    }
    
    func resetFindCursor() {
        browserManager.browserFindManager?.resetFindCursor()
    }
    
    func continueFind(progress: UnsafeMutablePointer<Double>, range: NSRangePointer) -> Bool {
        return browserManager.browserFindManager?.continueFind(progress: progress, range: range) ?? false
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

    // MARK: - AI Helpers

    func loadURL(_ url: URL, completion: @escaping @MainActor (Error?) -> ()) {
        Task {
            do {
                try await browserManager.loadURL(url)
                completion(nil)
            } catch {
                DLog("\(error)")
                completion(error)
            }
        }
    }

    func doWebSearch(for query:String, completion: @escaping @MainActor (Error?) -> ()) {
        if let url = browserManager.urlForWebSearch(query: query) {
            Task {
                do {
                    try await browserManager.loadURL(url)
                    completion(nil)
                } catch {
                    DLog("\(error)")
                    completion(error)
                }
            }
        }
    }

    func convertToMarkdown(skipChrome: Bool, completion: @escaping @MainActor (Result<String, Error>) -> ()) {
        Task {
            do {
                let result = try await browserManager.convertToMarkdown(skipChrome: skipChrome)
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }
    }

    struct FindOnPageResult: Codable {
        var line: Int
        var contextBefore: String?
        var matchingLine: String
        var contextAfter: String?
    }

    struct FindOnPageOutput: Codable {
        var results: [FindOnPageResult]
        var excessiveResultsDropped: Int
    }

    func findOnPage(query: String,
                    maxResults: Int,
                    contextLength: Int,
                    completion: @escaping @MainActor (Result<FindOnPageOutput, Error>) -> ()) {
        Task {
            do {
                let markdown = try await browserManager.convertToMarkdown(skipChrome: false)
                let lines = markdown.components(separatedBy: "\n")
                var results = [FindOnPageResult]()
                var dropped = 0
                for i in 0..<lines.count {
                    if lines[i].containsCaseInsensitive(query) {
                        var contextBefore = [String]()
                        do {
                            var j = i - 1
                            var length = 0
                            while length < contextLength && j >= 0 {
                                length += lines[j].count
                                contextBefore.insert(lines[j], at: 0)
                                j -= 1
                            }
                        }
                        var contextAfter = [String]()
                        do {
                            var j = i + 1
                            var length = 0
                            while length < contextLength && j < lines.count {
                                length += lines[j].count
                                contextAfter.append(lines[j])
                                j += 1
                            }
                        }
                        if results.count < maxResults {
                            results.append(FindOnPageResult(line: i,
                                                            contextBefore: contextBefore.joined(separator: "\n"),
                                                            matchingLine: lines[i],
                                                            contextAfter: contextAfter.joined(separator: "\n")))
                        } else {
                            dropped += 1
                        }
                    }
                }
                completion(.success(FindOnPageOutput(results: results,
                                                     excessiveResultsDropped: dropped)))
            } catch {
                completion(.failure(BrowserManagerError(errorDescription: "The page could not be converted to markdown for processing")))
            }
        }
    }
}

public struct BrowserManagerError: Error, LocalizedError {
    var errorDescription: String
}

// MARK: -  Overrides

@MainActor
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
        setupRestorationObserver()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        if !shouldDeferLoading() {
            loadDeferredURLIfNeeded()
        }
    }
    
    override func viewDidLayout() {
        super.viewDidLayout()
        layoutSubviews()
    }

    @objc
    func performFindPanelAction(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem else { return }

        switch NSFindPanelAction(rawValue: UInt(menuItem.tag)) {
        case .showFindPanel:
            browserManager.browserFindManager?.withoutForceSearch {
                delegate?.browserViewControllerShowFindPanel(self)
            }
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

@MainActor
extension iTermBrowserViewController {
    private func setupBackgroundView() {
        backgroundView = NSVisualEffectView()
        backgroundView.material = .contentBackground
        backgroundView.blendingMode = .behindWindow
        view.addSubview(backgroundView)
    }

    private func setupBrowserManager() {
        browserManager.delegate = self
    }

    private func setupToolbar() {
        toolbar = iTermBrowserToolbar()
        toolbar.indicatorsHelper = indicatorsHelper
        toolbar.delegate = self
        toolbar.setDevNullMode(browserManager.user == .devNull)
        indicatorsHelper.backgroundlessMode = true
        indicatorsHelper.indicatorSize = 20.0
        toolbar.configureIndicators(indicatorsHelper: indicatorsHelper, sessionGuid: sessionGuid)
        view.addSubview(toolbar)
    }

    private func setupWebView() {
        view.addSubview(browserManager.webView)
        view.addSubview(browserManager.userState.hiddenContainer)
        browserManager.userState.hiddenContainer.superviewObserver = { newSuperview in
            if newSuperview == nil {
                NotificationCenter.default.post(name: Self.didDeinitialize, object: nil)
            }
        }
        browserManager.userState.hiddenContainer.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        for view in browserManager.userState.hiddenContainer.subviews {
            view.frame = browserManager.userState.hiddenContainer.bounds
        }
    }

    private func setupShade() {
        shadeView.color = .black
        shadeView.isHidden = true
        view.addSubview(shadeView)
    }

    private func layoutSubviews() {
        let bounds = view.bounds
        
        // Background view - full coverage
        backgroundView.frame = bounds
        
        // Toolbar - top, full width, 44pt height
        toolbar.frame = NSRect(x: 0, y: bounds.height - 44,
                              width: bounds.width, height: 44)
        
        // WebView - below toolbar
        browserManager.webView.frame = NSRect(x: 0, y: 0,
                                            width: bounds.width,
                                            height: bounds.height - 44)
        
        // Shade view - full coverage
        shadeView.frame = bounds
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

// MARK: - Notification Handlers
@MainActor
extension iTermBrowserViewController {
    @objc
    private func otherBrowserViewControllerDidDeinitialize() {
        if browserManager.userState.hiddenContainer.superview == nil {
            logger.info("Taking ownership of hidden container for user state for \(browserManager.userState.user)")
            view.addSubview(browserManager.userState.hiddenContainer)
        }
    }
}

// MARK: - iTermBrowserToolbarDelegate

@MainActor
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

    func browserToolbarPermissionsForCurrentSite() async -> ([BrowserPermissionType: BrowserPermissionDecision], String)? {
        guard let url = browserManager.webView.url else {
            return nil
        }
        let origin = iTermBrowserPermissionManager.normalizeOrigin(from: url)
        var result = [BrowserPermissionType: BrowserPermissionDecision]()
        let manager = iTermBrowserPermissionManager(user: browserManager.user)
        for permissionType in BrowserPermissionType.allCases {
            let decision = await manager.getPermissionDecision(for: permissionType,
                                                               origin: origin)
            guard let decision else {
                continue
            }
            result[permissionType] = decision
        }
        return (result, origin)
    }

    func browserToolbarResetPermission(for key: BrowserPermissionType, origin: String) async {
        await iTermBrowserPermissionManager(user: browserManager.user).resetPermission(
            origin: origin,
            permissionType: key)
    }

    func browserToolbarUnmute(url: String) {
        browserManager.unmuteCurrentPage()
    }
    func browserToolbarIsCurrentPageMuted() -> Bool {
        return browserManager.currentPageIsMuted
    }
}

// MARK: - iTermBrowserManagerDelegate

@MainActor
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

    func browserManagerBroadcastWebViews(_ browserManager: iTermBrowserManager) -> [iTermBrowserWebView] {
        return delegate?.browserViewControllerBroadcastWebViews(self) ?? []
    }

    func browserManager(_ browserManager: iTermBrowserManager,
                        performTriggerAction action: BrowserTriggerAction) {
        switch action {
        case .stop:
            break
        }
    }

    func browserManager<T>(_ browserManager: iTermBrowserManager, announce: BrowserAnnouncement<T>) async -> T? {
        return await delegate?.browserViewController(self, announce: announce)
    }

    func browserManager(_ browserManager: iTermBrowserManager, handleKeyDown event: NSEvent) -> Bool {
        return delegate?.browserViewController(self, handleKeyDown: event) == true
    }
}

@MainActor
extension iTermBrowserViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(addNamedMark(_:)) {
            return canAddNamedMark
        }
        if menuItem.action == #selector(saveDocumentAs(_:)) {
            return browserManager.webView?.currentSelection?.isEmpty == false
        }
        return true
    }
}

// MARK: - Actions

@MainActor
extension iTermBrowserViewController {
    @objc(saveDocumentAs:)
    func saveDocumentAs(_ sender: Any) {
        let backup = browserManager.webView?.currentSelection
        Task {
            guard let window = view.window,
                    let string = await browserManager.webView.selectedText ?? backup else {
                return
            }

            let savePanel = iTermModernSavePanel()
            savePanel.defaultFilename = browserManager.webView.title ?? "Untitled"
            let response = await savePanel.beginSheetModal(for: window)
            if response == .OK,
                let item = savePanel.item,
                let location = SSHLocation(item) {
                try? await location.endpoint.create(location.path, content: string.lossyData)
            }
        }
    }

    @objc(saveContents:)
    func saveContents(_ sender: Any) {
        if let window = view.window {
            Task {
                await iTermBrowserPageSaver.pickDestinationAndSave(webView: browserManager.webView,
                                                                   parentWindow: window)
            }
        }
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

@MainActor
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

@MainActor
@objc(iTermBrowserView)
class iTermBrowserView: NSView {
    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        // Notify the view controller to relayout subviews
        if let viewController = self.nextResponder as? iTermBrowserViewController {
            viewController.viewDidLayout()
        }
    }
}

@MainActor
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

    func actionPerformingCopyMode(actions: String) {
        Task { @MainActor in
            let parser = VimKeyParser(actions)
            let events: [NSEvent]
            do {
                events = try parser.events()
            } catch {
                delegate?.browserViewController(self,
                                                showError: error.localizedDescription,
                                                suppressionKey: "NoSyncSuppressCopyModeErrors",
                                                identifier: "Copy Mode Error")
                DLog("\(error.localizedDescription)")
                return
            }
            await browserManager.copyModeHandler?.handle(events)
        }
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

@MainActor
extension iTermBrowserViewController: iTermBrowserFindManagerDelegate {
    func browserFindManager(_ manager: iTermBrowserFindManager, didUpdateResult result: iTermBrowserFindResultBundle) {
        delegate?.browserFindManager(manager, didUpdateResult: result)
    }
}

@MainActor
extension iTermBrowserViewController: iTermBrowserCopyModeHandlerDelegate {
    func copyModeHandlerShowFindPanel(_ sender: iTermBrowserCopyModeHandler) {
        delegate?.browserViewControllerShowFindPanel(self)
    }
}

@MainActor
extension iTermBrowserViewController: iTermBrowserTriggerHandlerDelegate {
    func browserTriggerEnterReaderMode() async {
        await browserManager.enterReaderMode()
    }

    func browserTriggerHighlightText(matchID: String, textColor: String?, backgroundColor: String?) {
        browserManager.triggerHandler?.highlightText(matchID: matchID,
                                                     textColor: textColor,
                                                     backgroundColor: backgroundColor)
    }

    func browserTriggerMakeHyperlink(matchID: String, url: String) {
        browserManager.triggerHandler?.makeHyperlink(matchID: matchID, url: url)
    }

    func triggerHandlerScope(_ sender: iTermBrowserTriggerHandler) -> iTermVariableScope? {
        return delegate?.browserViewControllerScope(self).0
    }

    func triggerHandlerObject(_ sender: iTermBrowserTriggerHandler) -> iTermObject? {
        return delegate?.browserViewControllerScope(self).1
    }
}
