//
//  iTermBrowserQuickLookViewController.swift
//  iTerm2SharedARC
//
//  Web Quick Look built on the built-in browser’s engine: it shares the browser’s persistent login
//  store and Safari user agent, and services popups (window.open) in small panels so OAuth sign-in
//  flows can complete. A slim bar shows the URL and offers to open the page elsewhere.
//

import AppKit
@preconcurrency import WebKit

@objc(iTermBrowserQuickLookViewController)
class iTermBrowserQuickLookViewController: NSViewController, WKUIDelegate, WKNavigationDelegate, NSWindowDelegate {
    private static let size = NSSize(width: 800, height: 600)
    private static let popupSize = NSSize(width: 500, height: 600)
    private static let barHeight = CGFloat(32)
    private static let margin = CGFloat(8)

    @objc let webView: WKWebView
    // Called once, on the first mouse-down inside the view.
    @objc var onUserInteraction: (() -> Void)?
    // The popover hosting this controller. The close button closes it.
    @objc weak var presentingPopover: NSPopover?
    // Set for previews opened by hovering a link. Until the user clicks into the preview, JavaScript
    // alert and confirm dialogs are answered without being shown (alert dismissed, confirm declined)
    // and pop-up windows are refused, so resting the pointer on a link can’t put up an app-modal
    // dialog or a window.
    @objc var suppressesInterruptionsUntilClicked = false

    private let initialURL: URL
    private var popups = [(panel: NSPanel, webView: WKWebView)]()
    private var urlLabel: NSTextField?
    private var clickWatcher: iTermQuickLookClickWatcher?
    private var tornDown = false
    private var userClicked = false

    var suppressesInterruptions: Bool {
        return suppressesInterruptionsUntilClicked && !userClicked
    }

    @objc(initWithURL:)
    init(url: URL) {
        initialURL = url
        webView = WKWebView(frame: NSRect(origin: .zero, size: Self.size),
                            configuration: Self.makeConfiguration())
        super.init(nibName: nil, bundle: nil)
        webView.customUserAgent = iTermBrowserEngineDefaults.safariUserAgent()
        webView.uiDelegate = self
        webView.navigationDelegate = self
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    private static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        let dataStore = iTermBrowserEngineDefaults.websiteDataStoreForRegularUser()
        iTermBrowserEngineDefaults.applyProxyConfiguration(to: dataStore)
        configuration.websiteDataStore = dataStore
        return configuration
    }

    // MARK: - View

    override func loadView() {
        let view = iTermFlippedView(frame: NSRect(origin: .zero, size: Self.size))
        view.autoresizesSubviews = true

        let closeButton = NSButton()
        closeButton.image = NSImage.it_image(forSymbolName: SFSymbol.xmark.rawValue,
                                             accessibilityDescription: String(localized: "BrowserQuickLook.CloseAccessibility",
                                                                              defaultValue: "Close preview",
                                                                              comment: "Accessibility description for the button that closes a web Quick Look preview"),
                                             fallbackImageName: "xmark",
                                             for: Self.self)
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.refusesFirstResponder = true
        closeButton.target = self
        closeButton.action = #selector(closeButtonPressed(_:))
        closeButton.frame = NSRect(x: Self.margin, y: 6, width: 20, height: 20)
        closeButton.autoresizingMask = [.maxXMargin, .maxYMargin]
        view.addSubview(closeButton)

        var right = Self.size.width - Self.margin
        // The ObjC helper always returns a name; the header just lacks nullability annotations.
        let browserName = NSWorkspace.shared.it_defaultBrowserName(for: initialURL) ?? ""
        let defaultBrowserButton = makeBarButton(
            title: String(localized: "BrowserQuickLook.OpenInDefaultBrowser",
                          defaultValue: "Open in \(browserName)",
                          comment: "Button in a web Quick Look preview that opens the page in the user’s default browser. The placeholder is the browser’s name, such as Safari."),
            action: #selector(openInDefaultBrowserPressed(_:)),
            right: &right)
        view.addSubview(defaultBrowserButton)

        let iTermBrowserButton = makeBarButton(
            title: String(localized: "BrowserQuickLook.OpenInITermBrowser",
                          defaultValue: "Open in iTerm2 Browser",
                          comment: "Button in a web Quick Look preview that opens the page in a tab of iTerm2’s built-in browser"),
            action: #selector(openInITermBrowserPressed(_:)),
            right: &right)
        view.addSubview(iTermBrowserButton)

        let labelX = NSMaxX(closeButton.frame) + Self.margin
        let label = NSTextField(labelWithString: initialURL.absoluteString)
        label.lineBreakMode = .byTruncatingMiddle
        label.textColor = .secondaryLabelColor
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        label.sizeToFit()
        label.frame = NSRect(x: labelX,
                             y: (Self.barHeight - label.frame.height) / 2,
                             width: max(0, right - labelX),
                             height: label.frame.height)
        label.autoresizingMask = [.width, .maxYMargin]
        view.addSubview(label)
        urlLabel = label

        webView.frame = NSRect(x: 0,
                               y: Self.barHeight,
                               width: Self.size.width,
                               height: Self.size.height - Self.barHeight)
        webView.autoresizingMask = [.width, .height]
        view.addSubview(webView)

        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.load(URLRequest(url: initialURL))
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        installMouseDownMonitor()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        removeMouseDownMonitor()
    }

    // Lays out a button right-aligned at `right` and moves `right` to its left edge.
    private func makeBarButton(title: String, action: Selector, right: inout CGFloat) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        button.refusesFirstResponder = true
        button.sizeToFit()
        let width = button.frame.width
        button.frame = NSRect(x: right - width,
                              y: (Self.barHeight - button.frame.height) / 2,
                              width: width,
                              height: button.frame.height)
        button.autoresizingMask = [.minXMargin, .maxYMargin]
        right -= width + Self.margin
        return button
    }

    // MARK: - Public

    // True if window belongs to this preview: its own window or one of its popups.
    @objc(ownsWindow:)
    func owns(window: NSWindow?) -> Bool {
        guard let window else {
            return false
        }
        if window === view.window {
            return true
        }
        return popups.contains { $0.panel === window }
    }

    @objc func tearDown() {
        if tornDown {
            return
        }
        tornDown = true
        removeMouseDownMonitor()
        webView.stopLoading()
        // stopLoading doesn't stop media that is already playing. Unload the page, as the legacy
        // preview's terminateWebView does, so audio stops even if something keeps the view alive.
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.loadHTMLString("<html/>", baseURL: nil)
        let panels = popups.map { $0.panel }
        for panel in panels {
            panel.close()
        }
        popups.removeAll()
    }

    // MARK: - Actions

    // The page to hand on to a browser. Only a web address is handed on; anything else (about:blank,
    // or a scheme a page navigated to) falls back to the address the preview opened.
    private var currentURL: URL {
        return Self.urlToHandOn(current: webView.url, initial: initialURL)
    }

    static func urlToHandOn(current: URL?, initial: URL) -> URL {
        if let current, iTermQuickLookDomainAllowlist.isWebURL(current) {
            return current
        }
        return initial
    }

    @objc private func closeButtonPressed(_ sender: Any?) {
        presentingPopover?.performClose(sender)
    }

    @objc private func openInITermBrowserPressed(_ sender: Any?) {
        let url = currentURL
        if !iTermController.sharedInstance().open(url, target: nil, openStyle: .tab, select: true) {
            DLog("Could not open \(url) in the built-in browser; using the default browser")
            openInDefaultBrowser(url)
        }
    }

    @objc private func openInDefaultBrowserPressed(_ sender: Any?) {
        openInDefaultBrowser(currentURL)
    }

    private func openInDefaultBrowser(_ url: URL) {
        NSWorkspace.shared.it_open(url, target: nil, style: .tab, window: view.window)
    }

    // MARK: - Mouse-down detection

    private func installMouseDownMonitor() {
        guard clickWatcher == nil else {
            return
        }
        clickWatcher = iTermQuickLookClickWatcher(view: view) { [weak self] in
            self?.userDidClick()
        }
    }

    // Called on the first mouse-down inside the view.
    func userDidClick() {
        userClicked = true
        let callback = onUserInteraction
        onUserInteraction = nil
        callback?()
    }

    private func removeMouseDownMonitor() {
        clickWatcher?.stop()
        clickWatcher = nil
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else {
            return nil
        }
        if suppressesInterruptions {
            DLog("Not opening a window from a preview the user hasn’t clicked into")
            return nil
        }
        if navigationAction.navigationType == .linkActivated {
            // A target=_blank link. Follow it in place rather than opening a window, but only to a
            // web address.
            if let url = navigationAction.request.url, iTermQuickLookDomainAllowlist.isWebURL(url) {
                webView.load(URLRequest(url: url))
            } else {
                DLog("Not following a target=_blank link to a non-web address")
            }
            return nil
        }
        // A script opened a window, as OAuth sign-in does. It must be a real web view created with
        // this configuration so that window.opener and postMessage work.
        return makePopup(configuration: configuration, url: navigationAction.request.url)
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let index = popups.firstIndex(where: { $0.webView === webView }) else {
            return
        }
        popups[index].panel.close()
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        if suppressesInterruptions {
            DLog("Not showing a JavaScript alert in a preview the user hasn’t clicked into")
            completionHandler()
            return
        }
        let warning = iTermWarning()
        warning.heading = String(localized: "BrowserManager.WebPageAlert", defaultValue: "Web Page Alert", comment: "Title for a JavaScript alert dialog")
        warning.title = message
        warning.actionLabels = [iTermLocalizedOK()]
        warning.warningType = .kiTermWarningTypePersistent
        warning.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        if suppressesInterruptions {
            DLog("Declining a JavaScript confirm in a preview the user hasn’t clicked into")
            completionHandler(false)
            return
        }
        let warning = iTermWarning()
        warning.heading = String(localized: "BrowserManager.WebPageConfirmation", defaultValue: "Web Page Confirmation", comment: "Title for a JavaScript confirmation dialog")
        warning.title = message
        warning.actionLabels = [iTermLocalizedOK(), iTermLocalizedCancel()]
        warning.cancelLabel = iTermLocalizedCancel()
        warning.warningType = .kiTermWarningTypePersistent
        let selection = warning.runModal()
        completionHandler(selection == .kiTermWarningSelection0)
    }

    // MARK: - WKNavigationDelegate

    // A preview shows only web pages. A main-frame navigation elsewhere (file:, a custom scheme) is
    // cancelled. about: stays allowed because tearDown unloads the page with about:blank. Subframes
    // are left alone: WebKit uses about:srcdoc, data: and blob: for them internally.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(Self.policy(for: navigationAction))
    }

    static func policy(for navigationAction: WKNavigationAction) -> WKNavigationActionPolicy {
        if let targetFrame = navigationAction.targetFrame, !targetFrame.isMainFrame {
            return .allow
        }
        guard let url = navigationAction.request.url else {
            return .cancel
        }
        if iTermQuickLookDomainAllowlist.isWebURL(url) || url.scheme?.lowercased() == "about" {
            return .allow
        }
        DLog("Cancelling a preview navigation to a non-web address: \(url.scheme ?? "(none)")")
        return .cancel
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if webView === self.webView, let url = webView.url {
            urlLabel?.stringValue = url.absoluteString
        }
    }

    // MARK: - Popups

    private func makePopup(configuration: WKWebViewConfiguration, url: URL?) -> WKWebView {
        let frame = NSRect(origin: .zero, size: Self.popupSize)
        let popupWebView = WKWebView(frame: frame, configuration: configuration)
        popupWebView.customUserAgent = webView.customUserAgent
        popupWebView.uiDelegate = self
        popupWebView.navigationDelegate = self
        popupWebView.autoresizingMask = [.width, .height]

        let panel = NSPanel(contentRect: frame,
                            styleMask: [.titled, .closable, .resizable],
                            backing: .buffered,
                            defer: false)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        // Localization unneeded: a host name.
        panel.title = url?.host ?? ""
        panel.contentView = popupWebView
        panel.delegate = self
        if let parentFrame = view.window?.frame {
            panel.setFrameTopLeftPoint(NSPoint(x: parentFrame.midX - frame.width / 2,
                                               y: parentFrame.maxY))
        } else {
            panel.center()
        }
        popups.append((panel: panel, webView: popupWebView))
        DLog("Opened Quick Look popup for \(url?.absoluteString ?? "(nil)")")
        panel.makeKeyAndOrderFront(nil)
        return popupWebView
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel,
              let index = popups.firstIndex(where: { $0.panel === panel }) else {
            return
        }
        let popup = popups.remove(at: index)
        popup.webView.stopLoading()
        popup.webView.uiDelegate = nil
        popup.webView.navigationDelegate = nil
        panel.delegate = nil
    }

    // MARK: - Testing

    var popupWebViews: [WKWebView] {
        return popups.map { $0.webView }
    }
}
