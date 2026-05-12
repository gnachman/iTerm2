//
//  MomentermBrowserPanelVC.swift
//  iTerm2
//
//  Right-side WKWebView panel that auto-follows http(s)://localhost URLs
//  printed in the panel's window. The panel does NOT use the full
//  iTermBrowserViewController — that one is built for first-class browser
//  tabs with history, bookmarks, extensions, etc. For a side preview we
//  just need a webview, a thin toolbar, and a pin toggle.
//

import AppKit
import WebKit

@objc(MomentermBrowserPanelDelegate)
protocol MomentermBrowserPanelDelegate: AnyObject {
    /// Return the GUID of the session whose output should drive auto-navigation,
    /// or nil if the panel should ignore detections (e.g. inactive window).
    func momentermBrowserPanelActiveSessionGUID() -> String?
}

@objc(MomentermBrowserPanelVC)
final class MomentermBrowserPanelVC: NSViewController {

    @objc weak var delegate: MomentermBrowserPanelDelegate?

    /// When true, ignore auto-detected URLs and stay on whatever the user manually loaded.
    @objc var isPinned: Bool = false {
        didSet { pinButton.state = isPinned ? .on : .off }
    }

    private var webView: WKWebView!
    private let toolbar = NSView()
    private let urlLabel = NSTextField(labelWithString: "")
    private let backButton = NSButton(title: "‹", target: nil, action: nil)
    private let forwardButton = NSButton(title: "›", target: nil, action: nil)
    private let reloadButton = NSButton(title: "⟳", target: nil, action: nil)
    private let pinButton = NSButton(title: "📌", target: nil, action: nil)
    private let openExternalButton = NSButton(title: "↗︎", target: nil, action: nil)

    private var currentURL: URL?
    private var navigationObserver: NSKeyValueObservation?

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 600))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        setupWebView()
        setupToolbar()
        layoutSubviews()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localhostDetected(_:)),
            name: MomentermLocalhostURLScanner.didDetectNotification,
            object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        navigationObserver?.invalidate()
    }

    // MARK: - Setup

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()  // keep cookies out of the main browser session
        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.allowsBackForwardNavigationGestures = true
        view.addSubview(webView)

        navigationObserver = webView.observe(\.url, options: [.new]) { [weak self] _, change in
            guard let self = self, let new = change.newValue, let url = new else { return }
            self.currentURL = url
            self.urlLabel.stringValue = url.absoluteString
        }
    }

    private func setupToolbar() {
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.addSubview(toolbar)

        let buttons: [NSButton] = [backButton, forwardButton, reloadButton, pinButton, openExternalButton]
        for btn in buttons {
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.bezelStyle = .regularSquare
            btn.isBordered = false
            btn.font = .systemFont(ofSize: 14, weight: .medium)
            btn.target = self
            toolbar.addSubview(btn)
        }
        backButton.action = #selector(goBack)
        forwardButton.action = #selector(goForward)
        reloadButton.action = #selector(reload)
        pinButton.action = #selector(togglePin)
        pinButton.setButtonType(.toggle)
        pinButton.toolTip = "Pin: stop auto-navigating when localhost URLs print"
        openExternalButton.action = #selector(openExternal)
        openExternalButton.toolTip = "Open in default browser"

        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        urlLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        urlLabel.textColor = .secondaryLabelColor
        urlLabel.lineBreakMode = .byTruncatingMiddle
        urlLabel.stringValue = "(waiting for localhost URL)"
        toolbar.addSubview(urlLabel)
    }

    private func layoutSubviews() {
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 32),

            webView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            backButton.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 6),
            backButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 22),

            forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 2),
            forwardButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            forwardButton.widthAnchor.constraint(equalToConstant: 22),

            reloadButton.leadingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 4),
            reloadButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            reloadButton.widthAnchor.constraint(equalToConstant: 22),

            urlLabel.leadingAnchor.constraint(equalTo: reloadButton.trailingAnchor, constant: 8),
            urlLabel.trailingAnchor.constraint(equalTo: pinButton.leadingAnchor, constant: -8),
            urlLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            pinButton.trailingAnchor.constraint(equalTo: openExternalButton.leadingAnchor, constant: -4),
            pinButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            pinButton.widthAnchor.constraint(equalToConstant: 24),

            openExternalButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -6),
            openExternalButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            openExternalButton.widthAnchor.constraint(equalToConstant: 22),
        ])
    }

    // MARK: - URL detection

    @objc private func localhostDetected(_ note: Notification) {
        guard !isPinned else { return }
        guard let urlString = note.userInfo?["url"] as? String,
              let sessionGUID = note.userInfo?["sessionGUID"] as? String else { return }
        guard let activeGUID = delegate?.momentermBrowserPanelActiveSessionGUID(),
              activeGUID == sessionGUID else { return }
        loadURLString(urlString)
    }

    // MARK: - Public

    @objc func loadURLString(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        if currentURL == url { return }  // avoid pointless reload
        webView.load(URLRequest(url: url))
    }

    /// Force a reload of the most recent URL. Useful when the user wants to
    /// see the result of a hot-reload that didn't change the URL.
    @objc func reloadCurrent() {
        if currentURL != nil {
            webView.reload()
        }
    }

    // MARK: - Actions

    @objc private func goBack() { webView.goBack() }
    @objc private func goForward() { webView.goForward() }
    @objc private func reload() { webView.reload() }
    @objc private func togglePin() {
        isPinned = (pinButton.state == .on)
    }
    @objc private func openExternal() {
        if let url = currentURL {
            NSWorkspace.shared.open(url)
        }
    }
}
