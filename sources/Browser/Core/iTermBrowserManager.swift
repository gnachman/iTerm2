//
//  iTermBrowserManager.swift
//  iTerm2
//
//  Created by George Nachman on 6/18/25.
//

@preconcurrency import WebKit
import Network
import WebExtensionsFramework

struct BrowserAnnouncement<T> {
    var message: String
    var style: iTermAnnouncementViewStyle
    struct Option {
        var title: String
        var identifier: T
    }
    var options: [Option]
    var identifier: String
}

@available(macOS 11.0, *)
@MainActor
protocol iTermBrowserManagerDelegate: AnyObject, iTermBrowserFindManagerDelegate, iTermBrowserTriggerHandlerDelegate {
    func browserManager(_ manager: iTermBrowserManager, didUpdateURL url: String?)
    func browserManager(_ manager: iTermBrowserManager, didUpdateTitle title: String?)
    func browserManager(_ manager: iTermBrowserManager, didUpdateFavicon favicon: NSImage?)
    func browserManager(_ manager: iTermBrowserManager, didUpdateCanGoBack canGoBack: Bool)
    func browserManager(_ manager: iTermBrowserManager, didUpdateCanGoForward canGoForward: Bool)
    func browserManager(_ manager: iTermBrowserManager, didStartNavigation navigation: WKNavigation?)
    func browserManager(_ manager: iTermBrowserManager, didFinishNavigation navigation: WKNavigation?)
    func browserManager(_ manager: iTermBrowserManager, didFailNavigation navigation: WKNavigation?, withError error: Error)
    func browserManager(_ manager: iTermBrowserManager, requestNewWindowForURL url: URL, configuration: WKWebViewConfiguration) -> iTermBrowserWebView?
    func browserManager(_ manager: iTermBrowserManager, openNewTabForURL url: URL)
    func browserManager(_ manager: iTermBrowserManager, openNewSplitPaneForURL url: URL, vertical: Bool)
    func browserManager(_ manager: iTermBrowserManager, openPasswordManagerForHost host: String?, forUser: Bool, didSendUserName: (() -> ())?)
    func browserManagerDidRequestSavePageAs(_ manager: iTermBrowserManager)
    func browserManagerDidRequestAddNamedMark(_ manager: iTermBrowserManager, atPoint point: NSPoint)
    func browserManager(_ manager: iTermBrowserManager, didChangeReaderModeState isActive: Bool)
    func browserManager(_ manager: iTermBrowserManager, didChangeDistractionRemovalState isActive: Bool)
    func browserManagerDidReceiveNamedMarkUpdate(_ manager: iTermBrowserManager)
    func browserManagerSetMouseInfo(
        _ browserManager: iTermBrowserManager,
        pointInView: NSPoint,
        button: Int,
        count: Int,
        modifiers: NSEvent.ModifierFlags,
        sideEffects: iTermClickSideEffects,
        state: iTermMouseState)
    func browserManager(_ browserManager: iTermBrowserManager,
                        doSmartSelectionAtPointInWindow point: NSPoint) async
    func browserManager(_ browserManager: iTermBrowserManager,
                        didHoverURL url: String?, frame: NSRect)
    func browserManagerDidBecomeFirstResponder(_ browserManager: iTermBrowserManager)
    
    // Onboarding delegate methods
    func browserManagerOnboardingEnableAdBlocker(_ manager: iTermBrowserManager)
    func browserManagerOnboardingEnableInstantReplay(_ manager: iTermBrowserManager)
    func browserManagerOnboardingCreateBrowserProfile(_ manager: iTermBrowserManager) -> String?
    func browserManagerOnboardingSwitchToProfile(_ manager: iTermBrowserManager, guid: String)
    func browserManagerOnboardingCheckBrowserProfileExists(_ manager: iTermBrowserManager) -> Bool
    func browserManagerOnboardingFindBrowserProfileGuid(_ manager: iTermBrowserManager) -> String?
    func browserManagerOnboardingGetSettings(_ manager: iTermBrowserManager) -> iTermBrowserOnboardingSettings
    func browserManager(_ browserManager: iTermBrowserManager, didCopyString: String)
    func browserManagerSmartSelectionRules(
        _ browserManager: iTermBrowserManager) -> [SmartSelectRule]
    func browserManagerRunCommand(_ browserManager: iTermBrowserManager, command: String)
    func browserManagerScope(_ browserManager: iTermBrowserManager) -> (iTermVariableScope, iTermObject)?
    func browserManagerShouldInterpolateSmartSelectionParameters(
        _ browserManager: iTermBrowserManager) -> Bool
    func browserManager(_ browserManager: iTermBrowserManager, openFile file: String)
    func browserManager(_ browserManager: iTermBrowserManager, performSplitPaneAction action: iTermBrowserSplitPaneAction)
    func browserManagerCurrentTabHasMultipleSessions(_ browserManager: iTermBrowserManager) -> Bool
    func browserManagerBroadcastWebViews(_ browserManager: iTermBrowserManager) -> [iTermBrowserWebView]
    func browserManager<T>(_ browserManager: iTermBrowserManager, announce: BrowserAnnouncement<T>) async -> T?
    func browserManager(_ browserManager: iTermBrowserManager, handleKeyDown event: NSEvent) -> Bool
}

@available(macOS 11.0, *)
@objc(iTermBrowserManager)
@MainActor
class iTermBrowserManager: NSObject, WKURLSchemeHandler, WKScriptMessageHandler {
    private static let adblockSettingsDidChange = NSNotification.Name("iTermBrowserManagerAdblockSettingsDidChange")

    weak var delegate: iTermBrowserManagerDelegate?  {
        didSet {
            triggerHandler?.delegate = delegate
        }
    }
    private(set) var webView: iTermBrowserWebView!
    private var lastFailedURL: URL?
    private var currentPageURL: URL?
    private let localPageManager: iTermBrowserLocalPageManager
    private let sshPageManager: iTermBrowserSSHPageManager
    private(set) var favicon: NSImage?
    private var _findManager = iTermBrowserFindManager.create()
    private var adblockManager: iTermBrowserAdblockManager?
    private var notificationHandler: iTermBrowserNotificationHandler?
    private var hoverLinkHandler = iTermBrowserHoverLinkHandler()
    private(set) var copyModeHandler = iTermBrowserCopyModeHandler.create()
    let passwordWriter = iTermBrowserPasswordWriter()
    private let selectionMonitor = iTermBrowserSelectionMonitor()
    private let contextMenuMonitor = iTermBrowserContextMenuMonitor()
    let namedMarkManager: iTermBrowserNamedMarkManager?
    let sessionGuid: String
    let historyController: iTermBrowserHistoryController
    private let navigationState: iTermBrowserNavigationState
    private var navigationCount = 0
    private let readerModeManager = iTermBrowserReaderModeManager()
    let autofillHandler = iTermBrowserAutofillHandler()
    let user: iTermBrowserUser
    private var currentMainFrameHTTPMethod: String?
    let userState: iTermBrowserUserState
    private let handlerProxy = iTermBrowserWebViewHandlerProxy()
    let triggerHandler: iTermBrowserTriggerHandler?
    private let audioHandler: iTermBrowserAudioHandler?
    private let editingDetector: iTermBrowserEditingDetectorHandler?
    private let graphDiscovery = iTermBrowserGraphDiscoveryHandler()
    private static var nextIdentifier = 1
    private lazy var identifier: Int = {
        defer {
            Self.nextIdentifier += 1
        }
        return Self.nextIdentifier
    }()
    private static var safariVersion = {
        Bundle(path: "/Applications/Safari.app")?.infoDictionary?["CFBundleShortVersionString"] as? String
    }()

    init(user: iTermBrowserUser,
         configuration: WKWebViewConfiguration?,
         sessionGuid: String,
         historyController: iTermBrowserHistoryController,
         navigationState: iTermBrowserNavigationState,
         profileObserver: iTermProfilePreferenceObserver,
         profileMutator: iTermProfilePreferenceMutator,
         pointerController: PointerController) {
        self.user = user
        self.userState = iTermBrowserUserState.instance(
            for: user,
            configuration: iTermBrowserUserState.Configuration(user: user),
            profileObserver: profileObserver,
            profileMutator: profileMutator)
        self.sessionGuid = sessionGuid
        self.historyController = historyController
        self.navigationState = navigationState
        self.localPageManager = iTermBrowserLocalPageManager(user: user,
                                                             historyController: historyController)
        self.sshPageManager = iTermBrowserSSHPageManager()
        self.namedMarkManager = iTermBrowserNamedMarkManager(user: user)
        self.triggerHandler = iTermBrowserTriggerHandler(profileObserver: profileObserver)
        self.audioHandler = iTermBrowserAudioHandler()
        self.editingDetector = iTermBrowserEditingDetectorHandler()

        super.init()

        handlerProxy.delegate = self
        localPageManager.delegate = self
        setupWebView(configuration: configuration,
                     profileObserver: profileObserver,
                     pointerController: pointerController)
        setupPermissionNotificationObserver()
        setupAdblockNotificationObserver()
    }
    
    deinit {
        // Remove KVO observer to prevent crashes
        webView?.removeObserver(self, forKeyPath: "title")
        if let webView = self.webView {
            let userState = self.userState
            Task { @MainActor in
                userState.unregisterWebView(webView)
            }
        }
    }

    private enum UserScripts: String {
        case consoleLog
        case notificationHandler
        case selectionMonitor
        case contextMenuMonitor
        case geolocation
        case passwordManager
        case autofillHandler
        case hoverLinkHandler
        case copyModeHandler
    }

    private func configure(_ configuration: WKWebViewConfiguration,
                           contentManager: BrowserExtensionUserContentManager) {
        switch user {
        case .regular(id: let userID):
            if #available(macOS 14, *) {
                let profileStore = WKWebsiteDataStore(forIdentifier: userID)
                configuration.websiteDataStore = profileStore
            }
        case .devNull:
            configuration.websiteDataStore = .nonPersistent()
        }

        // Configure proxy if enabled
        applyProxyConfiguration(to: configuration.websiteDataStore)

        var logErrors = ""
#if ITERM_DEBUG
        logErrors = iTermBrowserTemplateLoader.loadTemplate(named: "log-errors",
                                                            type: "js",
                                                            substitutions: [:])
#endif
        let js = iTermBrowserTemplateLoader.loadTemplate(named: "console-log",
                                                         type: "js",
                                                         substitutions: ["LOG_ERRORS": logErrors])
        configuration.userContentController.add(handlerProxy, contentWorld: .page, name: "iTerm2ConsoleLog")
        configuration.userContentController.add(handlerProxy, contentWorld: .defaultClient, name: "iTerm2ConsoleLog")
        configuration.userContentController.add(handlerProxy, contentWorld: .page, name: "iterm2-about:permissions")
        contentManager.add(userScript: BrowserExtensionUserContentManager.UserScript(
            code: "(function() {" + js + "})();",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            worlds: [.page, .defaultClient],
            identifier: UserScripts.consoleLog.rawValue))
        contentManager.add(userScript: .init(
            code: iTermBrowserTemplateLoader.load(template: "graph-discovery.js", substitutions: [:]),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            worlds: [graphDiscovery.world],
            identifier: "GraphDiscovery"))
        configuration.userContentController.add(handlerProxy,
                                                contentWorld: graphDiscovery.world,
                                                name: iTermBrowserGraphDiscoveryHandler.messageHandlerName)
        contentManager.add(userScript: .init(code: graphDiscovery.javascript,
                                             injectionTime: .atDocumentStart,
                                             forMainFrameOnly: false,
                                             worlds: [graphDiscovery.world],
                                             identifier: "GraphDiscovery"))
        // TODO: Ensure all of these handlers are stateless because related webviews (e.g., target=_blank) share them.
        if let notificationHandler {
            // This is a polyfill so it goes int he page world
            configuration.userContentController.add(handlerProxy, contentWorld: .page, name: iTermBrowserNotificationHandler.messageHandlerName)
            contentManager.add(userScript: BrowserExtensionUserContentManager.UserScript(
                code: notificationHandler.javascript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                worlds: [.page],
                identifier: UserScripts.notificationHandler.rawValue))
        }

        if let selectionMonitor {
            configuration.userContentController.add(handlerProxy, contentWorld: .defaultClient, name: iTermBrowserSelectionMonitor.messageHandlerName)
            contentManager.add(userScript: BrowserExtensionUserContentManager.UserScript(
                code: selectionMonitor.javascript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                worlds: [.defaultClient],
                identifier: UserScripts.selectionMonitor.rawValue))
        }

        if let contextMenuMonitor {
            configuration.userContentController.add(handlerProxy, contentWorld: .defaultClient, name: iTermBrowserContextMenuMonitor.messageHandlerName)
            contentManager.add(userScript: BrowserExtensionUserContentManager.UserScript(
                code: contextMenuMonitor.javascript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                worlds: [.defaultClient],
                identifier: UserScripts.contextMenuMonitor.rawValue))
        }

        let geolocationHandler = iTermBrowserGeolocationHandler.instance(for: user)
        if let geolocationHandler {
            // This goes in the page world because it is a polyfill meant to be used by pages.
            configuration.userContentController.add(handlerProxy, contentWorld: .page, name: iTermBrowserGeolocationHandler.messageHandlerName)
            contentManager.add(userScript: BrowserExtensionUserContentManager.UserScript(
                code: geolocationHandler.javascript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                worlds: [.page],
                identifier: UserScripts.geolocation.rawValue))
        }

        if let passwordManagerHandler = iTermBrowserPasswordManagerHandler.instance {
            configuration.userContentController.add(handlerProxy, contentWorld: .defaultClient, name: iTermBrowserPasswordManagerHandler.messageHandlerName)
            contentManager.add(userScript: BrowserExtensionUserContentManager.UserScript(
                code: passwordManagerHandler.javascript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false,
                worlds: [.defaultClient],
                identifier: UserScripts.passwordManager.rawValue))
        }

        if let autofillHandler {
            autofillHandler.delegate = self
            configuration.userContentController.add(handlerProxy, contentWorld: .defaultClient, name: iTermBrowserAutofillHandler.messageHandlerName)
            contentManager.add(userScript: BrowserExtensionUserContentManager.UserScript(
                code: autofillHandler.javascript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true,
                worlds: [.defaultClient],
                identifier: UserScripts.autofillHandler.rawValue))
        }

        if let hoverLinkHandler = hoverLinkHandler {
            configuration.userContentController.add(handlerProxy, contentWorld: .defaultClient, name: iTermBrowserHoverLinkHandler.messageHandlerName)
            contentManager.add(userScript: BrowserExtensionUserContentManager.UserScript(
                code: hoverLinkHandler.javascript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                worlds: [.defaultClient],
                identifier: UserScripts.hoverLinkHandler.rawValue))
        }

        if let copyModeHandler {
            contentManager.add(
                userScript: .init(code: copyModeHandler.javascript,
                                  injectionTime: .atDocumentStart,
                                  forMainFrameOnly: false,
                                  worlds: [.defaultClient],
                                  identifier: "CopyMode"))
        }

        if let triggerHandler {
            configuration.userContentController.add(
                handlerProxy,
                contentWorld: .defaultClient,
                name: iTermBrowserTriggerHandler.messageHandlerName)
            contentManager.add(
                userScript: .init(code: triggerHandler.javascript,
                                  injectionTime: .atDocumentStart,
                                  forMainFrameOnly: true,
                                  worlds: [.defaultClient],
                                  identifier: "TriggerHandler"))
        }
        if let editingDetector {
            configuration.userContentController.add(
                handlerProxy,
                contentWorld: .defaultClient,
                name: iTermBrowserEditingDetectorHandler.messageHandlerName)
            contentManager.add(
                userScript: .init(code: editingDetector.javascript,
                                  injectionTime: .atDocumentStart,
                                  forMainFrameOnly: false,
                                  worlds: [.defaultClient],
                                  identifier: "EditingDetector"))
        }
        configuration.userContentController.add(
            handlerProxy,
            contentWorld: .defaultClient,
            name: iTermBrowserAudioHandler.messageHandlerName)
        configuration.userContentController.add(
            handlerProxy,
            contentWorld: .page,
            name: iTermBrowserAudioHandler.messageHandlerName)
        if let audioHandler {
            contentManager.add(
                userScript: .init(code: audioHandler.javascript(world: .page),
                                  injectionTime: .atDocumentStart,
                                  forMainFrameOnly: false,
                                  worlds: [.page],
                                  identifier: iTermBrowserAudioHandler.messageHandlerName))
            contentManager.add(
                userScript: .init(code: audioHandler.javascript(world: .defaultClient),
                                  injectionTime: .atDocumentStart,
                                  forMainFrameOnly: false,
                                  worlds: [.defaultClient],
                                  identifier: iTermBrowserAudioHandler.messageHandlerName))
        }

        if let browserFindManager {
            contentManager.add(
                userScript: .init(code: browserFindManager.javascript,
                                  injectionTime: .atDocumentStart,
                                  forMainFrameOnly: false,
                                  worlds: [browserFindManager.world],
                                  identifier: iTermBrowserFindManager.messageHandlerName))
            configuration.userContentController.add(
                handlerProxy,
                contentWorld: browserFindManager.world,
                name: iTermBrowserFindManager.messageHandlerName)
        }
        configuration.userContentController.add(readerModeManager,
                                                contentWorld: .defaultClient,
                                                name: "readerMode")

        // Add message handler for named mark updates
        if namedMarkManager != nil {
            configuration.userContentController.add(handlerProxy,
                                                    contentWorld: .defaultClient,
                                                    name: iTermBrowserNamedMarkManager.messageHandlerName)
            configuration.userContentController.add(handlerProxy,
                                                    contentWorld: .defaultClient,
                                                    name: iTermBrowserNamedMarkManager.layoutUpdateHandlerName)
        }
        // Register custom URL scheme handler for iterm2-about: URLs
        configuration.setURLSchemeHandler(handlerProxy, forURLScheme: iTermBrowserSchemes.about)
        configuration.setURLSchemeHandler(handlerProxy, forURLScheme: iTermBrowserSchemes.ssh)
    }

    private func setupWebView(configuration preferredConfiguration: WKWebViewConfiguration?,
                              profileObserver: iTermProfilePreferenceObserver,
                              pointerController: PointerController) {
        // Setup adblocking. This has to be done early because it's needed when applying the proxy configuration.
        setupAdblocking()
        
        let notificationHandler = iTermBrowserNotificationHandler(user: user)
        self.notificationHandler = notificationHandler
        
        let configuration: WKWebViewConfiguration
        let contentManager: BrowserExtensionUserContentManager?
        if let preferredConfiguration {

            configuration = preferredConfiguration
            contentManager = nil
        } else {
            let prefs = WKPreferences()
            
            // block JS-only popups
            prefs.javaScriptCanOpenWindowsAutomatically = false
            configuration = WKWebViewConfiguration()
            configuration.preferences = prefs
            contentManager = BrowserExtensionUserContentManager(
                userContentController: configuration.userContentController,
                userScriptFactory: BrowserExtensionUserScriptFactory())

            configure(configuration, contentManager: contentManager!)
        }
        audioHandler?.delegate = self
        // Setup reader mode
        readerModeManager.delegate = self

        webView = iTermBrowserWebView(frame: .zero,
                                      configuration: configuration,
                                      pointerController: pointerController)
        if let safariBundle = Bundle(path: "/Applications/Safari.app"),
           let safariVersion = safariBundle.infoDictionary?["CFBundleShortVersionString"] as? String {
            webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
            "Version/\(safariVersion) Safari/605.1.15"
        } else {
            webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
            "Version/16.4 Safari/605.1.15"
        }

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.pageZoom = profileObserver.value(KEY_BROWSER_ZOOM) / 100
        profileObserver.observeDouble(key: KEY_BROWSER_ZOOM) { [weak self] (_, newValue) in
            guard let self else { return }
            let existing = self.webView.pageZoom
            let proposed = newValue / 100.0
            if abs(existing - proposed) > 0.001 {
                self.webView.pageZoom = proposed
            }
        }
        webView.browserDelegate = self
        // Enable back/forward navigation
        webView.allowsBackForwardNavigationGestures = true

        // Observe title changes
        webView.addObserver(self, forKeyPath: "title", options: [.new], context: nil)

        // TODO: This is going to cause problems for extensions. If you open a link with target=_blank then the new webview won't have a content
        // manager. I don't know what will happen if we do not register a webview with the extension manager.
        if let contentManager {
            userState.registerWebView(webView, contentManager: contentManager)
        }
        copyModeHandler?.webView = webView

        // Initialize find manager
        _findManager?.webView = webView
        _findManager?.delegate = self
        triggerHandler?.webView = webView

        // Start updates if needed
        adblockManager?.updateRulesIfNeeded()

        // Setup settings delegate
        setupSettingsDelegate()
    }

    private func setupPermissionNotificationObserver() {
        let key = iTermBrowserPermissionManager.permissionRevokedOriginKey
        NotificationCenter.default.addObserver(
            forName: iTermBrowserPermissionManager.permissionRevokedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let origin = notification.userInfo?[key] as? String else {
                return
            }
            
            Task {
                await self.handlePermissionRevoked(for: origin)
            }
        }
    }

    private func setupAdblockNotificationObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(adblockSettingsDidChange(_:)),
            name: iTermBrowserManager.adblockSettingsDidChange,
            object: nil)
    }

    @MainActor
    private func handlePermissionRevoked(for origin: String) async {
        // Check if this WebView contains content from the revoked origin
        let containsOrigin = await checkWebViewContainsOrigin(origin)
        
        if containsOrigin {
            DLog("Reloading browser session \(sessionGuid) due to revoked permission for origin: \(origin)")
            reload()
        }
    }
    
    @MainActor
    private func checkWebViewContainsOrigin(_ origin: String) async -> Bool {
        // Check main frame origin
        if let mainURL = webView.url {
            let mainOrigin = iTermBrowserPermissionManager.normalizeOrigin(from: mainURL)
            if mainOrigin == origin {
                return true
            }
        }
        
        // Check iframe origins using JavaScript loaded from template
        let checkIframesScript = iTermBrowserTemplateLoader.loadTemplate(named: "check-iframe-origins",
                                                                          type: "js",
                                                                          substitutions: [:])
        
        do {
            let result = try await webView.safelyEvaluateJavaScript(checkIframesScript, contentWorld: .page)
            if let origins = result as? [String] {
                return origins.contains(origin)
            }
        } catch {
            DLog("Failed to check iframe origins: \(error)")
            // If JavaScript fails, be conservative and assume it might contain the origin
            // if the main frame is the same origin (safer to reload than miss permission revocation)
            if let mainURL = webView.url {
                let mainOrigin = iTermBrowserPermissionManager.normalizeOrigin(from: mainURL)
                return mainOrigin == origin
            }
        }
        
        return false
    }
    
    // MARK: - Public Interface

    var currentPageIsMuted: Bool {
        audioHandler?.mutedFrames.isEmpty == false
    }

    func unmuteCurrentPage() {
        Task {
            for frame in audioHandler?.mutedFrames ?? [] {
                await audioHandler?.unmute(webView, frame: frame)
            }
        }
    }

    struct PageContent {
        var title: String
        var content: String
    }

    func pageContent() async -> PageContent? {
        guard webView.url != nil else {
            return nil
        }
        guard let title = webView.title ?? webView.url?.absoluteString else {
            return nil
        }
        guard let content = await readerModeManager.plainTextContent(webView: webView) else {
            return nil
        }
        return .init(title: title, content: content)
    }

    func enterReaderMode() async {
        await readerModeManager.enterReaderMode(webView: webView)
    }

    func toggleReaderMode() {
        readerModeManager.toggle(webView: webView)
    }
    
    var isReaderModeActive: Bool {
        return readerModeManager.isActive
    }
    
    func toggleDistractionRemoval() {
        Task {
            await readerModeManager.toggleDistractionRemovalMode(webView: webView)
        }
    }
    
    var isDistractionRemovalActive: Bool {
        return readerModeManager.isDistractionRemovalActive
    }
    
    var currentHTTPMethod: String? {
        return currentMainFrameHTTPMethod
    }
    
    func loadURL(_ urlString: String) {
        guard let url = normalizeURL(urlString) else {
            // TODO: Handle invalid URL
            return
        }
        loadURL(url, continuation: nil)
    }

    func loadURL(_ url: URL, continuation: CheckedContinuation<Void, Error>?) {
        if let continuation {
            navigationState.willLoadURL(url, continuation: continuation)
        } else {
            navigationState.willLoadURL(url)
        }
        localPageManager.resetAllHandlerState()
        lastFailedURL = nil  // Reset failed URL when loading new URL
        favicon = nil  // Clear favicon when loading new URL
        let request = URLRequest(url: url)
        webView.load(request)
    }

    func loadURL(_ url: URL) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            loadURL(url, continuation: continuation)
        }
    }

    func goBack() {
        if webView.canGoBack {
            favicon = nil  // Clear favicon when navigating
            webView.goBack()
        }
    }
    
    func goForward() {
        if webView.canGoForward {
            favicon = nil  // Clear favicon when navigating
            webView.goForward()
        }
    }
    
    func reload() {
        // Always reload current page
        webView.reload()
    }
    
    func stop() {
        webView.stopLoading()
    }
    
    func getBackHistoryItems() -> [iTermBrowserHistoryItem] {
        var items: [iTermBrowserHistoryItem] = []
        let backList = webView.backForwardList.backList
        
        for (index, item) in backList.enumerated().reversed() {
            let steps = -(backList.count - index)  // Most recent back item = -1, next = -2, etc.
            let historyItem = iTermBrowserHistoryItem(
                title: item.title ?? "",
                url: item.url.absoluteString,
                steps: steps
            )
            items.append(historyItem)
        }
        
        return items
    }
    
    func getForwardHistoryItems() -> [iTermBrowserHistoryItem] {
        var items: [iTermBrowserHistoryItem] = []
        let forwardList = webView.backForwardList.forwardList
        
        for (index, item) in forwardList.enumerated() {
            let steps = index + 1  // Positive steps for going forward
            let historyItem = iTermBrowserHistoryItem(
                title: item.title ?? "",
                url: item.url.absoluteString,
                steps: steps
            )
            items.append(historyItem)
        }
        
        return items
    }
    
    func navigateHistory(steps: Int) {
        if steps == -1 && webView.canGoBack {
            webView.goBack()
        } else if steps == 1 && webView.canGoForward {
            webView.goForward()
        } else if steps != 0 {
            // For multi-step navigation, use go(to:)
            let backForwardList = webView.backForwardList
            var targetItem: WKBackForwardListItem?
            
            if steps < 0 {
                // Going back
                let backList = backForwardList.backList
                let index = abs(steps) - 1
                if index < backList.count {
                    targetItem = backList[backList.count - 1 - index]
                }
            } else {
                // Going forward
                let forwardList = backForwardList.forwardList
                let index = steps - 1
                if index < forwardList.count {
                    targetItem = forwardList[index]
                }
            }
            
            if let targetItem = targetItem {
                favicon = nil  // Clear favicon when navigating
                webView.go(to: targetItem)
            }
        }
    }
    
    // MARK: - Find Support
    
    @objc var browserFindManager: iTermBrowserFindManager? {
        _findManager
    }
    
    @objc var supportsFinding: Bool {
        return _findManager != nil
    }
    
    private func showErrorPage(for error: Error, failedURL: URL?) {
        localPageManager.showErrorPage(for: error, failedURL: failedURL, webView: webView)
    }
    
    private func isDownloadRelatedError(_ error: Error) -> Bool {
        let nsError = error as NSError
        
        // Check for common download-related error codes
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorCancelled:
                // Navigation was cancelled, likely due to download policy
                return true
            default:
                break
            }
        }
        
        // Check for WebKit-specific cancellation
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 {
            // Frame load interrupted
            return true
        }
        
        return false
    }

    // MARK: - AI Helpers

    func convertToMarkdown(skipChrome: Bool) async throws -> String {
        return try await readerModeManager.markdown(fromContentsOf: webView, skipChrome: skipChrome)
    }

    // MARK: - Private Helpers

    private func notifyDelegateOfUpdates() {
        delegate?.browserManager(self, didUpdateURL: webView.url?.absoluteString)
        
        // For file: URLs, use the filename as title
        var title = webView.title
        if let url = webView.url, url.scheme == "file" {
            title = url.lastPathComponent
        }
        
        delegate?.browserManager(self, didUpdateTitle: title)
        delegate?.browserManager(self, didUpdateCanGoBack: webView.canGoBack)
        delegate?.browserManager(self, didUpdateCanGoForward: webView.canGoForward)
    }
    
    private func notifyDelegateOfFaviconUpdate() {
        delegate?.browserManager(self, didUpdateFavicon: favicon)
    }
    

    private func loadFavicon(from url: URL) {
        // Use URLSession to download favicon
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self,
                  let data = data,
                  error == nil,
                  let image = NSImage(data: data) else {
                return
            }
            
            DispatchQueue.main.async {
                self.favicon = image
                self.notifyDelegateOfFaviconUpdate()
            }
        }.resume()
    }
    
    private func injectMessageHandlersIfNeeded() {
        guard let currentURL = webView.url?.absoluteString else { return }

        localPageManager.setupMessageHandlers(for: webView, currentURL: currentURL)
        
        // Register message handler if needed
        if localPageManager.shouldRegisterMessageHandler(for: currentURL) {
            webView.configuration.userContentController.add(handlerProxy, contentWorld: .defaultClient, name: currentURL)
            localPageManager.markMessageHandlerRegistered(for: currentURL)
            localPageManager.injectJavaScript(for: currentURL, webView: webView)
            DLog("Registered message handler for \(currentURL)")
        }
    }
}

// MARK: - iTermBrowserWebViewDelegate

@available(macOS 11.0, *)
@MainActor
extension iTermBrowserManager: iTermBrowserWebViewDelegate {
    func webViewDidChangeEffectiveAppearance(_ webView: iTermBrowserWebView) {
        updateFavicon()
    }

    func webView(_ webView: iTermBrowserWebView, handleKeyDown event: NSEvent) -> Bool {
        if delegate?.browserManager(self, handleKeyDown: event) == true {
            return true
        }
        if copyModeHandler?.enabled != true {
            return false
        }
        copyModeHandler?.handle(event)
        return true
    }

    func webView(_ webView: iTermBrowserWebView,
                 didReceiveEvent event: iTermBrowserWebView.Event) {
        for receiver in delegate?.browserManagerBroadcastWebViews(self) ?? [] {
            if receiver == webView {
                continue
            }
            receiver.receivingBroadcast = true
            defer {
                receiver.receivingBroadcast = false
            }
            switch event {
            case .insert(text: let text):
                receiver.insertText(text)
            case .doCommandBySelector(let sel):
                receiver.doCommand(by: sel)
            }
        }
    }
    
    func webViewSetMouseInfo(_ webView: iTermBrowserWebView,
                             pointInView: NSPoint,
                             button: Int,
                             count: Int,
                             modifiers: NSEvent.ModifierFlags,
                             sideEffects: iTermClickSideEffects,
                             state: iTermMouseState) {
        delegate?.browserManagerSetMouseInfo(
            self,
            pointInView: pointInView,
            button: button,
            count: count,
            modifiers: modifiers,
            sideEffects: sideEffects,
            state: state)
    }

    func webViewDidBecomeFirstResponder(_ webView: iTermBrowserWebView) {
        delegate?.browserManagerDidBecomeFirstResponder(self)
    }

    func webViewDidRequestRemoveElement(_ webView: iTermBrowserWebView, at point: NSPoint) {
        readerModeManager.removeElement(webView: webView, at: point)
    }

    func webViewDidRequestViewSource(_ webView: iTermBrowserWebView) {
        viewPageSource()
    }

    func webViewDidRequestSavePageAs(_ webView: iTermBrowserWebView) {
        savePageAs()
    }

    func webViewDidRequestAddNamedMark(_ webView: iTermBrowserWebView, atPoint point: NSPoint) {
        delegate?.browserManagerDidRequestAddNamedMark(self, atPoint: point)
    }

    func webViewDidRequestDoSmartSelection(_ webView: iTermBrowserWebView,
                                           pointInWindow point: NSPoint) {
        Task {
            await delegate?.browserManager(self, doSmartSelectionAtPointInWindow: point)
        }
    }

    func webViewOpenURLInNewTab(_ webView: iTermBrowserWebView, url: URL) {
        delegate?.browserManager(self, openNewTabForURL: url)
    }

    func webViewDidHoverURL(_ webView: iTermBrowserWebView, url: String?, frame: NSRect) {
        delegate?.browserManager(self, didHoverURL: url, frame: frame)

        // If clearing hover, also clear it in JavaScript
        if url == nil {
            hoverLinkHandler?.clearHover(in: webView)
        }
    }

    func webViewDidCopy(_ webView: iTermBrowserWebView, string: String) {
        delegate?.browserManager(self, didCopyString: string)
    }

    func webViewSearchEngineName(_ webView: iTermBrowserWebView) -> String? {
        guard let url = URL(string: iTermAdvancedSettingsModel.searchCommand()),
              let parts = url.host?.lowercased().components(separatedBy: ".") else {
            return nil
        }

        if parts.count < 2 {
            return nil
        }
        let domain = parts[parts.count - 2] + "." + parts[parts.count - 1]
        switch domain {
        case "google.com":
            return "Google"
        case "bing.com":
            return "Bing"
        case "baidu.com":
            return "Baidu"
        case "yandex.com":
            return "Yandex"
        case "duckduckgo.com":
            return "DuckDuckGo"
        case "ecosia.org":
            return "Ecosia"
        case "startpage.com":
            return "Startpage"
        case "searxng.org":
            return "SearXNG"
        case "swisscows.ch":
            return "Swisscows"
        case "dogpile.com":
            return "Dogpile"
        case "metacrawler.com":
            return "MetaCrawler"
        case "mojeek.com":
            return "Mojeek"
        case "kagi.com":
            return "Kagi"
        case "qwant.com":
            return "Qwant"
        case "excite.com":
            return "Excite"
        case "hotbot.com":
            return "HotBot"
        case "lycos.com":
            return "Lycos"
        case "sogou.com":
            return "Sogou"
        case "youdao.com":
            return "Youdao"
        case "webcrawler.com":
            return "WebCrawler"
        default:
            return nil
        }
    }

    func urlForWebSearch(query: String) -> URL? {
        guard let escapedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: iTermAdvancedSettingsModel.searchCommand().replacingOccurrences(of: "%@", with: escapedQuery)) else {
            return nil
        }
        return url
    }

    func webViewPerformWebSearch(_ webView: iTermBrowserWebView, query: String) {
        if let url = urlForWebSearch(query: query) {
            delegate?.browserManager(self, openNewTabForURL: url)
        }
    }

    func webViewSmartSelectionRules(_ webView: iTermBrowserWebView) -> [SmartSelectRule] {
        return delegate?.browserManagerSmartSelectionRules(self) ?? []
    }

    func webViewRunCommand(_ webView: iTermBrowserWebView, command: String) {
        delegate?.browserManagerRunCommand(self, command: command)
    }

    func webViewScope(_ webView: iTermBrowserWebView) -> (iTermVariableScope, iTermObject)? {
        delegate?.browserManagerScope(self)
    }

    func webViewScopeShouldInterpolateSmartSelectionParameters(_ webView: iTermBrowserWebView) -> Bool {
        delegate?.browserManagerShouldInterpolateSmartSelectionParameters(self) ?? false
    }

    func webViewOpenFile(_ webView: iTermBrowserWebView, file: String) {
        delegate?.browserManager(self, openFile: file)
    }

    func webViewPerformSplitPaneAction(_ webView: iTermBrowserWebView, action: iTermBrowserSplitPaneAction) {
        delegate?.browserManager(self, performSplitPaneAction: action)
    }

    func webViewCurrentTabHasMultipleSessions(_ webView: iTermBrowserWebView) -> Bool {
        return delegate?.browserManagerCurrentTabHasMultipleSessions(self) ?? false
    }
}

// MARK: - WKScriptMessageHandler

@available(macOS 11.0, *)
extension iTermBrowserManager {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // Handle console.{log,debug,error} messages separately since they come as String
        switch message.name {
        case "iTerm2ConsoleLog":
            if let obj = message.body as? [String: String], let logMessage = obj["msg"], let level = obj["level"] {
                switch level {
                case "debug":
                    DLog("Javascript Console: " + logMessage)
#if ITERM_DEBUG
                    let id = "#\(identifier)"
                    iTermScriptHistory.sharedInstance().addBrowserLoggingEntryIfNeeded(id)
                    iTermScriptHistoryEntry.browserEntry(id).addOutput(logMessage + "\n") {}
#endif
                default:
#if ITERM_DEBUG
                    NSFuckingLog("%@", "Javascript Console: \(logMessage)")
#else
                    XLog("Javascript Console: \(logMessage)")
#endif
                    let id = "#\(identifier)"
                    iTermScriptHistory.sharedInstance().addBrowserLoggingEntryIfNeeded(id)
                    iTermScriptHistoryEntry.browserEntry(id).addOutput(logMessage + "\n") {}
                }
            }

        case iTermBrowserFindManager.messageHandlerName:
            _findManager?.handleMessage(webView: webView, message: message)

        case iTermBrowserGraphDiscoveryHandler.messageHandlerName:
            graphDiscovery.handleMessage(webView: webView, message: message)

        case iTermBrowserNotificationHandler.messageHandlerName:
            notificationHandler?.handleMessage(webView: webView, message: message)

        case iTermBrowserGeolocationHandler.messageHandlerName:
            iTermBrowserGeolocationHandler.instance(for: user)?.handleMessage(webView: webView, message: message)

        case iTermBrowserPasswordManagerHandler.messageHandlerName:
            switch iTermBrowserPasswordManagerHandler.instance?.handleMessage(
                webView: webView,
                message: message) {
            case .none:
                break
            case .openPasswordManagerForUser:
                delegate?.browserManager(
                    self,
                    openPasswordManagerForHost: webView.url?.host,
                    forUser: true,
                    didSendUserName: nil)
            case .openPasswordManagerForPassword:
                delegate?.browserManager(
                    self,
                    openPasswordManagerForHost: webView.url?.host,
                    forUser: false,
                    didSendUserName: nil)
            case .openPasswordManagerForBoth(passwordID: let passwordID):
                let count = navigationCount
                delegate?.browserManager(
                    self,
                    openPasswordManagerForHost: webView.url?.host,
                    forUser: true) { [weak self] in
                        guard let self,
                              navigationCount == count,
                              let webView else {
                            return
                        }
                        let passwordWriter = self.passwordWriter
                        Task {
                            _ = await passwordWriter.focus(webView: webView,
                                                           id: passwordID)
                        }
                    }
            }
            
        case iTermBrowserHoverLinkHandler.messageHandlerName:
            if let hoverInfo = hoverLinkHandler?.handleMessage(webView: webView, message: message) {
                // Pass frame in webview coordinates - delegate will handle conversion as needed
                NSLog("BrowserManager: WebView frame %@ -> delegate", NSStringFromRect(hoverInfo.frame))
                delegate?.browserManager(self, didHoverURL: hoverInfo.url, frame: hoverInfo.frame)
            }
            
        case iTermBrowserAutofillHandler.messageHandlerName:
            _ = autofillHandler?.handleMessage(webView: webView, message: message)

        case iTermBrowserSelectionMonitor.messageHandlerName:
            selectionMonitor?.handleMessage(message, webView: webView)

        case iTermBrowserContextMenuMonitor.messageHandlerName:
            contextMenuMonitor?.handleMessage(message, webView: webView)
            
        case iTermBrowserNamedMarkManager.messageHandlerName:
            if namedMarkManager?.handleMessage(webView: webView, message: message) == true {
                delegate?.browserManagerDidReceiveNamedMarkUpdate(self)
            }
            
        case iTermBrowserNamedMarkManager.layoutUpdateHandlerName:
            namedMarkManager?.handleLayoutUpdateMessage(webView: webView, message: message)

        case iTermBrowserTriggerHandler.messageHandlerName:
            if let triggerHandler {
                Task {
                    for action in await triggerHandler.handleMessage(webView: webView, message: message) {
                        switch action {
                        case .stop:
                            return
                        }
                    }
                }
            }
        case iTermBrowserAudioHandler.messageHandlerName:
            audioHandler?.handleMessage(webView: webView, message: message)

        case iTermBrowserFindManager.messageHandlerName:
            browserFindManager?.handleMessage(webView: webView, message: message)

        case iTermBrowserEditingDetectorHandler.messageHandlerName:
            editingDetector?.handleMessage(webView: webView, message: message)

        default:
            DLog(message.name)

            // For other messages, require dictionary format and current URL
            guard let currentURL = currentPageURL else {
                return
            }

            // Let the local page manager handle the message
            let _ = localPageManager.handleMessage(message, webView: webView, currentURL: currentURL)
        }
    }
}

// MARK: - WKURLSchemeHandler

@available(macOS 11.0, *)
extension iTermBrowserManager {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "iTermBrowserManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }

        switch url.scheme {
        case iTermBrowserSchemes.about:
            if !localPageManager.handleURLSchemeTask(urlSchemeTask, url: url) {
                urlSchemeTask.didFailWithError(NSError(domain: "iTermBrowserManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown URL scheme"]))
            }
        case iTermBrowserSchemes.ssh:
            if !sshPageManager.handleURLSchemeTask(urlSchemeTask, url: url) {
                urlSchemeTask.didFailWithError(NSError(domain: "iTermBrowserManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown URL scheme"]))
            }
        default:
            urlSchemeTask.didFailWithError(NSError(domain: "iTermBrowserManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown URL scheme"]))
        }
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        switch urlSchemeTask.request.url?.scheme {
        case iTermBrowserSchemes.about:
            break
        case iTermBrowserSchemes.ssh:
            sshPageManager.stop(urlSchemeTask: urlSchemeTask)
        default:
            break
        }
    }
}

// MARK: - WKNavigationDelegate

@available(macOS 11.0, *)
extension iTermBrowserManager: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        navigationCount += 1
        readerModeManager.resetForNavigation()
        delegate?.browserManager(self, didStartNavigation: navigation)
        copyModeHandler?.enabled = false
        audioHandler?.disabled = false
        audioHandler?.mutedFrames = []
        graphDiscovery.willNavigate()
        self.webView.isEditingText = false
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // URL is now committed, update UI
        notifyDelegateOfUpdates()
        
        // Track the current page URL for security checks
        if let url = webView.url {
            currentPageURL = url
        }
        
        // Setup message handlers early for our about: pages
        injectMessageHandlersIfNeeded()
        
        Task {
            await historyController.recordVisit(for: webView.url, title: webView.title)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        it_assert(webView === self.webView)
        // Clear failed URL on successful navigation to a real page (not error pages)
        if webView.url != iTermBrowserErrorHandler.errorURL {
            lastFailedURL = nil
        }

        // Track the current page URL for security checks
        if let url = webView.url {
            currentPageURL = url
        }

        // Conditionally inject message handlers for our about: pages
        injectMessageHandlersIfNeeded()

        notifyDelegateOfUpdates()

        // Update permission states for geolocation
        if let url = webView.url {
            let originString = iTermBrowserPermissionManager.normalizeOrigin(from: url)
            Task {
                await iTermBrowserGeolocationHandler.instance(for: user)?.updatePermissionState(
                    for: originString,
                    webView: self.webView)
            }
        }

        // Try to detect and load favicon
        updateFavicon()

        // Update title in browser history if available
        historyController.titleDidChange(for: webView.url, title: webView.title)

        delegate?.browserManager(self, didFinishNavigation: navigation)
        navigationState.didCompleteLoading(error: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        DLog("🔌 didFailNavigation: domain=\(nsError.domain) code=\(nsError.code) — \(nsError.localizedDescription)")
        let failedURL = navigationState.lastRequestedURL

        navigationState.didCompleteLoading(error: error)

        // Don't show error page for download-related cancellations
        if isDownloadRelatedError(error) {
            delegate?.browserManager(self, didFailNavigation: navigation, withError: error)
            return
        }

        // Only show error page if this isn't the same URL that already failed
        if failedURL != lastFailedURL && failedURL != nil {
            showErrorPage(for: error, failedURL: failedURL)
            lastFailedURL = failedURL
        }

        delegate?.browserManager(self, didFailNavigation: navigation, withError: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        DLog("didFailProvisionalNavigation: domain=\(nsError.domain) code=\(nsError.code) — \(nsError.localizedDescription)")
        let failedURL = navigationState.lastRequestedURL

        navigationState.didCompleteLoading(error: error)

        // Don't show error page for download-related cancellations
        if isDownloadRelatedError(error) {
            delegate?.browserManager(self, didFailNavigation: navigation, withError: error)
            return
        }

        // Only show error page if this isn't the same URL that already failed
        if failedURL != lastFailedURL && failedURL != nil {
            showErrorPage(for: error, failedURL: failedURL)
            lastFailedURL = failedURL
        }

        delegate?.browserManager(self, didFailNavigation: navigation, withError: error)
        copyModeHandler?.enabled = false
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        it_assert(webView === self.webView)
        localPageManager.unregisterAllMessageHandlers(webView: self.webView)

        // Track HTTP method for main frame navigations only
        if navigationAction.targetFrame?.isMainFrame == true {
            currentMainFrameHTTPMethod = navigationAction.request.httpMethod
        }
        
        if navigationAction.navigationType == .linkActivated {
            if navigationAction.modifierFlags.contains(.command),
               let url = navigationAction.request.url {
                if navigationAction.modifierFlags.contains(.option) {
                    if navigationAction.modifierFlags.contains(.shift) {
                        delegate?.browserManager(self, openNewSplitPaneForURL: url, vertical: false)
                        decisionHandler(.cancel)
                    } else {
                        delegate?.browserManager(self, openNewSplitPaneForURL: url, vertical: true)
                        decisionHandler(.cancel)
                    }
                } else {
                    delegate?.browserManager(self, openNewTabForURL: url)
                    decisionHandler(.cancel)
                }
                return
            }
        }

        // Store the target URL for this navigation so we can use it in error handlers
        // But don't overwrite if this is our error page navigation
        if let targetURL = navigationAction.request.url, targetURL != iTermBrowserErrorHandler.errorURL {
            navigationState.willLoadURL(targetURL)
        }

        // Store the transition type for the upcoming navigation
        navigationState.willNavigate(action: navigationAction)

        // Popup blocking logic
        guard let targetURL = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        // Always allow our internal pages and prepare message handlers early
        if targetURL.absoluteString.hasPrefix(iTermBrowserSchemes.about + ":") {
            let urlString = targetURL.absoluteString
            localPageManager.prepareForNavigation(to: targetURL)

            // Pre-register message handler if needed
            if localPageManager.shouldRegisterMessageHandler(for: urlString) {
                webView.configuration.userContentController.removeScriptMessageHandler(
                    forName: urlString,
                    contentWorld: .page)
                webView.configuration.userContentController.add(handlerProxy,
                                                                contentWorld: .page,
                                                                name: urlString)
                localPageManager.markMessageHandlerRegistered(for: urlString)
                DLog("Pre-registered message handler for \(urlString)")
            }

            decisionHandler(.allow)
            return
        }

        // Check for popup behavior
        if navigationAction.targetFrame == nil {
            // This is a popup (no target frame = new window/tab)
            switch navigationAction.navigationType {
            case .linkActivated:
                // User clicked a link - request new window from delegate
                let _ = delegate?.browserManager(self,
                                                 requestNewWindowForURL: targetURL,
                                                 configuration: webView.configuration.copy() as! WKWebViewConfiguration)
                decisionHandler(.cancel)
                return
            case .other:
                // Automatic popup (JavaScript without user interaction) - block it
                DLog("Blocked automatic popup to: \(targetURL)")
                decisionHandler(.cancel)
                return
            default:
                // Block other popup types for safety
                DLog("Blocked popup navigation type \(navigationAction.navigationType.rawValue) to: \(targetURL)")
                decisionHandler(.cancel)
                return
            }
        }

        // Regular navigation in same frame - allow
        decisionHandler(.allow)
    }

    @available(macOS 11, *)
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {

        // Check if this should be downloaded instead of displayed
        guard let response = navigationResponse.response as? HTTPURLResponse else {
            decisionHandler(.allow)
            return
        }

        // Check content disposition and content type for download triggers
        let contentDisposition = response.allHeaderFields["Content-Disposition"] as? String ?? ""
        let contentType = response.mimeType ?? ""

        // Download if:
        // 1. Content-Disposition header indicates attachment
        // 2. Content type is not something WKWebView can display well
        if #available(macOS 11.3, *) {
            if contentDisposition.lowercased().contains("attachment") ||
                !canWebViewDisplay(contentType: contentType) {
                decisionHandler(.download)
                return
            }
        }

        decisionHandler(.allow)
    }

    @available(macOS 11.3, *)
    func webView(_ webView: WKWebView,
                 navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) {
        handleDownload(download, sourceURL: navigationAction.request.url)
    }

    @available(macOS 11.3, *)
    func webView(_ webView: WKWebView,
                 navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
        handleDownload(download, sourceURL: navigationResponse.response.url)
    }

    @available(macOS 11.3, *)
    private func canWebViewDisplay(contentType: String) -> Bool {
        let lowerContentType = contentType.lowercased()

        // Content types that WKWebView can display well
        let displayableTypes = [
            "text/html",
            "text/plain",
            "text/css",
            "text/javascript",
            "application/javascript",
            "application/json",
            "application/xml",
            "text/xml",
            "image/png",
            "image/jpeg",
            "image/jpg",
            "image/gif",
            "image/svg+xml",
            "image/webp",
            "application/pdf",
            "video/mp4",
            "video/webm",
            "audio/mp3",
            "audio/mpeg",
            "audio/wav",
            "audio/webm"
        ]

        // If no content type specified, assume it can be displayed (let WKWebView decide)
        if lowerContentType.isEmpty {
            return true
        }

        return displayableTypes.contains { lowerContentType.hasPrefix($0) }
    }

    @available(macOS 11.3, *)
    private func handleDownload(_ download: WKDownload, sourceURL: URL?) {
        guard let sourceURL = sourceURL else { return }

        let suggestedFilename = sourceURL.lastPathComponent.isEmpty ?
        "download" : sourceURL.lastPathComponent

        let browserDownload = iTermBrowserDownload(
            wkDownload: download,
            sourceURL: sourceURL,
            suggestedFilename: suggestedFilename
        )

        // Start the download (adds to FileTransferManager)
        browserDownload.download()
    }
}

// MARK: - WKUIDelegate

@available(macOS 11.0, *)
extension iTermBrowserManager: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil, let url = navigationAction.request.url else {
            return nil
        }
        it_assert(webView === self.webView)
        localPageManager.unregisterAllMessageHandlers(webView: self.webView)
        return delegate?.browserManager(self,
                                        requestNewWindowForURL: url,
                                        configuration: configuration)
    }
    
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        // Handle JavaScript alerts
        let alert = NSAlert()
        alert.messageText = "Web Page Alert"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }
    
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        // Handle JavaScript confirmations
        let alert = NSAlert()
        alert.messageText = "Web Page Confirmation"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        completionHandler(response == .alertFirstButtonReturn)
    }
    
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        // Handle file input elements (e.g., <input type="file">)
        guard let window = webView.window else {
            completionHandler(nil)
            return
        }
        
        let panel = iTermOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else {
                completionHandler(nil)
                return
            }
            
            // Convert iTermOpenPanelItems to URLs
            var selectedURLs: [URL] = []
            let group = DispatchGroup()
            
            for item in panel.items {
                group.enter()
                item.urlPromise.then { url in
                    selectedURLs.append(url as URL)
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                // Respect multiple selection setting
                if parameters.allowsMultipleSelection {
                    completionHandler(selectedURLs)
                } else {
                    completionHandler(selectedURLs.isEmpty ? nil : [selectedURLs.first!])
                }
            }
        }
    }

    @objc private func viewPageSource() {
        // Get the current page's HTML source
        guard let url = webView.url else {
            return
        }
        
        // Try to fetch the original source from the network first
        fetchOriginalSource(url: url) { [weak self] originalSource in
            guard let self = self else { return }
            
            if let originalSource = originalSource {
                // Got original source from network
                DispatchQueue.main.async {
                    self.showSourceInBrowser(htmlSource: originalSource, url: url)
                }
            } else {
                // Fallback to DOM source if network fetch fails
                self.webView.safelyEvaluateJavaScript(iife("return document.documentElement.outerHTML"),
                                                      contentWorld: .page) { [weak self] result, error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        DLog("Error getting page source: \(error)")
                        return
                    }
                    
                    guard let htmlSource = result as? String else {
                        DLog("Failed to get HTML source")
                        return
                    }
                    
                    DispatchQueue.main.async {
                        self.showSourceInBrowser(htmlSource: htmlSource, url: url)
                    }
                }
            }
        }
    }
    
    private func fetchOriginalSource(url: URL, completion: @escaping (String?) -> Void) {
        // Skip non-HTTP URLs
        guard iTermBrowserMetadata.supportedSchemes.contains(url.scheme?.lowercased() ?? "") else {
            completion(nil)
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                DLog("Failed to fetch original source: \(error)")
                completion(nil)
                return
            }
            
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                DLog("Invalid response when fetching original source")
                completion(nil)
                return
            }
            
            // Try to determine encoding from response headers
            var encoding = String.Encoding.utf8
            if let textEncodingName = httpResponse.textEncodingName {
                let cfEncoding = CFStringConvertIANACharSetNameToEncoding(textEncodingName as CFString)
                if cfEncoding != kCFStringEncodingInvalidId {
                    encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
                }
            }
            
            if let htmlSource = String(data: data, encoding: encoding) {
                completion(htmlSource)
            } else {
                // Try UTF-8 as fallback
                completion(String(data: data, encoding: .utf8))
            }
        }
        
        task.resume()
    }
    
    private func showSourceInBrowser(htmlSource: String, url: URL) {
        localPageManager.showSourcePage(htmlSource: htmlSource, url: url, webView: webView)
    }
    
    @objc private func savePageAs() {
        delegate?.browserManagerDidRequestSavePageAs(self)
    }
    
    // MARK: - Media Capture Permissions
    
    @available(macOS 12.0, *)
    func webView(_ webView: WKWebView,
                 decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
                 initiatedBy frame: WKFrameInfo,
                 type: WKMediaCaptureType) async -> WKPermissionDecision {
        it_assert(webView === self.webView)
        return await iTermBrowserPermissionManager(user: user).handleMediaCapturePermissionRequest(
            from: self.webView,
            origin: origin,
            frame: frame,
            type: type
        )
    }
}

@available(macOS 11.0, *)
@MainActor
extension iTermBrowserManager: iTermBrowserLocalPageManagerDelegate {
    func localPageManagerDidUpdateAdblockSettings(_ manager: iTermBrowserLocalPageManager) {
        NotificationCenter.default.post(name: Self.adblockSettingsDidChange, object: nil)
    }

    func localPageManagerDidRequestAdblockUpdate(_ manager: iTermBrowserLocalPageManager) {
        // Force update of adblock rules
        forceAdblockUpdate()
    }
    
    func localPageManagerDidNavigateToURL(_ manager: iTermBrowserLocalPageManager, url: String) {
        // Navigate to the URL in the current browser
        loadURL(url)
    }
    
    func localPageManagerWebView(_ manager: iTermBrowserLocalPageManager) -> iTermBrowserWebView? {
        return webView
    }
    
    func localPageManagerExtensionManager(_ manager: iTermBrowserLocalPageManager) -> iTermBrowserExtensionManagerProtocol? {
        return userState.extensionManager
    }
    
    func localPageManagerOnboardingEnableAdBlocker(_ manager: iTermBrowserLocalPageManager) {
        delegate?.browserManagerOnboardingEnableAdBlocker(self)
    }
    
    func localPageManagerOnboardingEnableInstantReplay(_ manager: iTermBrowserLocalPageManager) {
        delegate?.browserManagerOnboardingEnableInstantReplay(self)
    }
    
    func localPageManagerOnboardingCreateBrowserProfile(_ manager: iTermBrowserLocalPageManager) -> String? {
        return delegate?.browserManagerOnboardingCreateBrowserProfile(self)
    }
    
    func localPageManagerOnboardingSwitchToProfile(_ manager: iTermBrowserLocalPageManager, guid: String) {
        delegate?.browserManagerOnboardingSwitchToProfile(self, guid: guid)
    }
    
    func localPageManagerOnboardingCheckBrowserProfileExists(_ manager: iTermBrowserLocalPageManager) -> Bool {
        return delegate?.browserManagerOnboardingCheckBrowserProfileExists(self) ?? false
    }
    
    func localPageManagerOnboardingFindBrowserProfileGuid(_ manager: iTermBrowserLocalPageManager) -> String? {
        return delegate?.browserManagerOnboardingFindBrowserProfileGuid(self)
    }
    
    func localPageManagerOnboardingGetSettings(_ manager: iTermBrowserLocalPageManager) -> iTermBrowserOnboardingSettings {
        return delegate?.browserManagerOnboardingGetSettings(self) ?? iTermBrowserOnboardingSettings(adBlockerEnabled: false, instantReplayEnabled: false)
    }
}

@available(macOS 11.0, *)
@MainActor
extension iTermBrowserManager {
    // MARK: - Settings Integration

    @objc func setupSettingsDelegate() {
        // Settings delegate is set when context is created
    }

    @objc func notifySettingsPageOfAdblockUpdate(success: Bool, error: String? = nil) {
        // Find the settings page webview and update its status
        if webView.url == iTermBrowserSettingsHandler.settingsURL {
            localPageManager.notifySettingsPageOfAdblockUpdate(success: success, error: error, webView: webView)
        }
    }
    
    func updateProxyConfiguration() {
        applyProxyConfiguration(to: webView.configuration.websiteDataStore)
    }

    private func applyProxyConfiguration(to dataStore: WKWebsiteDataStore) {
        guard #available(macOS 14.0, *) else { return }

        if iTermAdvancedSettingsModel.browserProxyEnabled() {
            let proxyHost = iTermAdvancedSettingsModel.browserProxyHost() ?? "127.0.0.1"
            let proxyPort = iTermAdvancedSettingsModel.browserProxyPort()

            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(proxyHost), port: NWEndpoint.Port(integerLiteral: UInt16(proxyPort)))
            let proxyConfig = ProxyConfiguration(httpCONNECTProxy: endpoint)
            dataStore.proxyConfigurations = [proxyConfig]
            DLog("Configured browser proxy: \(proxyHost):\(proxyPort)")
            return
        }
    }
}

@available(macOS 11.0, *)
@MainActor
extension iTermBrowserManager {

    // MARK: - Key-Value Observing
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "title", let webView = object as? iTermBrowserWebView, webView == self.webView {
            // Title changed - notify delegate
            notifyDelegateOfUpdates()
            
            // Update history with new title if we have a current URL
            if let url = webView.url {
                historyController.titleDidChange(for: url, title: webView.title)
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    // MARK: - Adblock Integration

    @objc func setupAdblocking() {
        // Use shared adblock manager
        adblockManager = iTermBrowserAdblockManager.shared
        
        // Listen for adblock notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(adblockRulesDidUpdate),
            name: iTermBrowserAdblockManager.didUpdateRulesNotification,
            object: iTermBrowserAdblockManager.shared
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(adblockDidFail(_:)),
            name: iTermBrowserAdblockManager.didFailWithErrorNotification,
            object: iTermBrowserAdblockManager.shared
        )
    }

    @objc func updateAdblockSettings() {
        // Called when settings change
        adblockManager?.updateRulesIfNeeded()
    }

    @objc func forceAdblockUpdate() {
        // Force update of adblock rules
        adblockManager?.forceUpdate()
    }

    // MARK: - Adblock Notification Handlers

    @objc private func adblockSettingsDidChange(_ notification: Notification) {
        // Update adblock rules when settings change
        updateAdblockSettings()
        // Also update proxy configuration since the delegate is shared
        updateProxyConfiguration()
    }

    @objc private func adblockRulesDidUpdate() {
        // Apply or remove rules based on settings
        updateWebViewContentRules()

        // Notify settings page if it's open
        notifySettingsPageOfAdblockUpdate(success: true)
    }
    
    @objc private func adblockDidFail(_ notification: Notification) {
        guard let error = notification.userInfo?[iTermBrowserAdblockManager.errorKey] as? Error else {
            return
        }
        
        // Forward to delegate for user notification
        // For now, just log the error
        print("Adblock error: \(error.localizedDescription)")

        // Notify settings page if it's open
        notifySettingsPageOfAdblockUpdate(success: false, error: error.localizedDescription)
    }

    // MARK: - Private Implementation

    private func updateWebViewContentRules() {
        let userContentController = webView.configuration.userContentController

        // Remove existing adblock rules
        userContentController.removeAllContentRuleLists()

        // Add new rules if adblock is enabled
        if iTermAdvancedSettingsModel.webKitAdblockEnabled(),
           let ruleList = adblockManager?.getRuleList() {
            userContentController.add(ruleList)
        }
    }
}

// MARK: - iTermBrowserReaderModeManagerDelegate

@available(macOS 11.0, *)
@MainActor
extension iTermBrowserManager: iTermBrowserReaderModeManagerDelegate {
    func readerModeManager(_ manager: iTermBrowserReaderModeManager, didChangeActiveState isActive: Bool) {
        delegate?.browserManager(self, didChangeReaderModeState: isActive)
    }
    
    func readerModeManager(_ manager: iTermBrowserReaderModeManager, didChangeDistractionRemovalState isActive: Bool) {
        delegate?.browserManager(self, didChangeDistractionRemovalState: isActive)
    }
}

@available(macOS 11.0, *)
@MainActor
extension iTermBrowserManager: iTermBrowserAutofillHandlerDelegate {
    func autoFillHandler(_ handler: iTermBrowserAutofillHandler,
                         requestAutofillForHost host: String,
                         fields: [[String: Any]]) {
        NSLog("Autofill requested for host: \(host) with \(fields.count) fields")

        Task {
            let contactSource = iTermBrowserAutofillContactSource()
            do {
                let fieldData = try await contactSource.prepareAutofillData(for: fields)
                if !fieldData.isEmpty {
                    await handler.fillFields(fieldData)
                } else {
                    NSLog("No contact data available for autofill")
                }
            } catch {
                NSLog("Failed to get contact data for autofill: \(error)")
            }
        }
    }

#if DEBUG
    func debugAutofillFields() {
        guard let webView = webView else { return }
        let js = "if (window.debugAutofillFields) { window.debugAutofillFields(); }"
        webView.safelyEvaluateJavaScript(js) { result, error in
            if let error = error {
                NSLog("Debug autofill fields error: \(error)")
            }
        }
    }
#endif

    private func updateFavicon() {
        Task {
            do {
                switch try await detectFavicon(webView: webView,
                                               appearance: webView.effectiveAppearance,
                                               isRetina: (webView.window?.backingScaleFactor ?? 2.0) > 1) {
                case .left(let image):
                    self.favicon = image
                    notifyDelegateOfFaviconUpdate()
                case .right(let url):
                    loadFavicon(from: url)
                }
            } catch {
                DLog("Failed to detect favicon: \(error)")
            }
        }
    }
}

@MainActor
extension iTermBrowserUserState.Configuration {
    init(user: iTermBrowserUser) {
        switch user {
        case .devNull:
            extensionsAllowed = false
            persistentStorageDisallowed = true
        default:
            extensionsAllowed = true
            persistentStorageDisallowed = false
        }
    }
}

@MainActor
extension iTermBrowserManager: iTermBrowserFindManagerDelegate {
    func browserFindManager(_ manager: iTermBrowserFindManager, didUpdateResult result: iTermBrowserFindResultBundle) {
        delegate?.browserFindManager(manager, didUpdateResult: result)
    }
}

extension iTermBrowserManager: iTermBrowserAudioHandlerDelegate {
    func browserAudioHandlerDidStartPlaying(_ sender: iTermBrowserAudioHandler, inFrame frame: WKFrameInfo) {
        guard let url = webView.url else {
            NSLog("%@", "Audio: no url")
            return
        }
        let origin = iTermBrowserPermissionManager.normalizeOrigin(from: url)
        Task {
            guard webView.url == url else {
                NSLog("%@", "Audio: url changed")
                return
            }
            let decision = await iTermBrowserPermissionManager(user: user).getPermissionDecision(
                for: .audioPlayback,
                origin: origin)
            switch decision {
            case .denied:
                NSLog("%@", "Audio denied for \(origin). Muting.")
                await audioHandler?.mute(webView, frame: frame)
                return
            case .granted:
                NSLog("%@", "Audio granted for \(origin). Doing nothing.")
                return
            case .none:
                await audioHandler?.mute(webView, frame: frame)
                enum Action {
                    case allowOnce
                    case allowAlways
                    case denyOnce
                    case denyAlways
                }
                let announcement = BrowserAnnouncement(
                    message: "Audio was muted. Allow playback by \(origin)?",
                    style: .kiTermAnnouncementViewStyleQuestion,
                    options: [.init(title: "Allow _Once", identifier: Action.allowOnce),
                              .init(title: "Allow _Always", identifier: Action.allowAlways),
                              .init(title: "_Deny Once", identifier: Action.denyOnce),
                              .init(title: "De_ny Always", identifier: Action.denyAlways) ],
                    identifier: "NoSyncMuteAudio_\(origin)")
                switch await delegate?.browserManager(self, announce: announcement) {
                case .allowOnce:
                    if webView.url == url {
                        NSLog("%@", "Audio allowed once \(origin). Disabling audio handler.")
                        audioHandler?.disabled = true
                        await audioHandler?.unmute(webView, frame: frame)
                    }
                case .allowAlways:
                    NSLog("%@", "Audio allowed always for \(origin).")
                    await iTermBrowserPermissionManager(user: user).savePermissionDecision(origin: origin,
                                                                                           permissionType: .audioPlayback,
                                                                                           decision: .granted)
                    await audioHandler?.unmute(webView, frame: frame)
                case .denyOnce:
                    NSLog("%@", "Audio denied once for \(origin). Doing nothing.")
                    audioHandler?.disabled = true
                    break
                case .denyAlways:
                    NSLog("%@", "Audio denied always for \(origin).")
                    await iTermBrowserPermissionManager(user: user).savePermissionDecision(origin: origin,
                                                                                           permissionType: .audioPlayback,
                                                                                           decision: .denied)
                case .none:
                    // Was closed without selecting an item
                    NSLog("%@", "Audio: announcement closed without making a selection")
                    break
                }
            }
        }
    }
}
