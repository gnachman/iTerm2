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

    /// Toggle whether the panel is embedded inline or in its own floating window.
    func momentermBrowserPanelRequestDetachToggle()

    /// Close (hide) the panel.
    func momentermBrowserPanelRequestClose()
}

@objc(MomentermBrowserPanelVC)
final class MomentermBrowserPanelVC: NSViewController {

    @objc weak var delegate: MomentermBrowserPanelDelegate?

    /// When true, the toolbar button shows the "detached" icon and the
    /// delegate manages the floating window. Toggling re-parents the view.
    @objc var isDetached: Bool = false {
        didSet { refreshDetachButtonIcon() }
    }

    private var webView: WKWebView!
    private let toolbar = NSView()
    private let urlField = NSTextField()
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let reloadButton = NSButton()
    private let zoomOutButton = NSButton()
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private let zoomInButton = NSButton()
    private let detachButton = NSButton()
    private let closeButton = NSButton()

    private var currentURL: URL?
    private var navigationObserver: NSKeyValueObservation?
    private let zoomLevels: [CGFloat] = [0.5, 0.67, 0.75, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]
    private var currentZoomIndex: Int = 5  // 1.0

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
            // Don't clobber the field while the user is mid-edit.
            if self.urlField.currentEditor() == nil {
                self.urlField.stringValue = url.absoluteString
            }
        }
    }

    private func setupToolbar() {
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.addSubview(toolbar)

        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        func configureSymbolButton(_ btn: NSButton, symbol: String, accessibility: String, selector: Selector, tip: String) {
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibility)?.withSymbolConfiguration(cfg)
            btn.imagePosition = .imageOnly
            btn.bezelStyle = .regularSquare
            btn.isBordered = false
            btn.contentTintColor = .secondaryLabelColor
            btn.target = self
            btn.action = selector
            btn.toolTip = tip
            toolbar.addSubview(btn)
        }

        configureSymbolButton(backButton, symbol: "chevron.left",
                              accessibility: "Back", selector: #selector(goBack), tip: "Back")
        configureSymbolButton(forwardButton, symbol: "chevron.right",
                              accessibility: "Forward", selector: #selector(goForward), tip: "Forward")
        configureSymbolButton(reloadButton, symbol: "arrow.clockwise",
                              accessibility: "Reload", selector: #selector(reload), tip: "Reload")
        configureSymbolButton(zoomOutButton, symbol: "minus.magnifyingglass",
                              accessibility: "Zoom out", selector: #selector(zoomOut), tip: "Zoom out")
        configureSymbolButton(zoomInButton, symbol: "plus.magnifyingglass",
                              accessibility: "Zoom in", selector: #selector(zoomIn), tip: "Zoom in")
        configureSymbolButton(detachButton, symbol: "rectangle.portrait.and.arrow.right",
                              accessibility: "Detach", selector: #selector(detachToggle),
                              tip: "Detach into a separate window")
        configureSymbolButton(closeButton, symbol: "xmark",
                              accessibility: "Close", selector: #selector(closeTapped), tip: "Close panel")
        refreshDetachButtonIcon()

        zoomLabel.translatesAutoresizingMaskIntoConstraints = false
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        zoomLabel.textColor = .tertiaryLabelColor
        zoomLabel.alignment = .center
        zoomLabel.toolTip = "Page zoom — double-click to reset"
        let resetClick = NSClickGestureRecognizer(target: self, action: #selector(resetZoom))
        resetClick.numberOfClicksRequired = 2
        zoomLabel.addGestureRecognizer(resetClick)
        toolbar.addSubview(zoomLabel)

        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        urlField.placeholderString = "Type a URL and press Enter"
        urlField.bezelStyle = .roundedBezel
        urlField.isBordered = true
        urlField.isEditable = true
        urlField.isSelectable = true
        urlField.target = self
        urlField.action = #selector(urlFieldSubmit)
        urlField.lineBreakMode = .byTruncatingMiddle
        toolbar.addSubview(urlField)
    }

    private func layoutSubviews() {
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 34),

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

            urlField.leadingAnchor.constraint(equalTo: reloadButton.trailingAnchor, constant: 8),
            urlField.trailingAnchor.constraint(equalTo: zoomOutButton.leadingAnchor, constant: -8),
            urlField.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            zoomOutButton.trailingAnchor.constraint(equalTo: zoomLabel.leadingAnchor, constant: -2),
            zoomOutButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            zoomOutButton.widthAnchor.constraint(equalToConstant: 22),

            zoomLabel.trailingAnchor.constraint(equalTo: zoomInButton.leadingAnchor, constant: -2),
            zoomLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            zoomLabel.widthAnchor.constraint(equalToConstant: 38),

            zoomInButton.trailingAnchor.constraint(equalTo: detachButton.leadingAnchor, constant: -6),
            zoomInButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            zoomInButton.widthAnchor.constraint(equalToConstant: 22),

            detachButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),
            detachButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            detachButton.widthAnchor.constraint(equalToConstant: 22),

            closeButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
        ])
    }

    private func refreshDetachButtonIcon() {
        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let symbol = isDetached ? "rectangle.portrait.and.arrow.forward" : "rectangle.portrait.and.arrow.right"
        detachButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
        detachButton.toolTip = isDetached ? "Re-attach to terminal window" : "Detach into a separate window"
    }

    // MARK: - URL detection

    @objc private func localhostDetected(_ note: Notification) {
        // Don't overwrite while the user is mid-edit in the URL field.
        if urlField.currentEditor() != nil { return }
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

    @objc private func detachToggle() {
        delegate?.momentermBrowserPanelRequestDetachToggle()
    }

    @objc private func closeTapped() {
        delegate?.momentermBrowserPanelRequestClose()
    }

    @objc private func urlFieldSubmit() {
        var input = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty { return }
        // Be forgiving: accept "localhost:3000" / "example.com" without scheme.
        if !input.contains("://") {
            input = "http://\(input)"
        }
        guard let url = URL(string: input) else { return }
        webView.load(URLRequest(url: url))
    }

    @objc private func zoomIn() { setZoomIndex(currentZoomIndex + 1) }
    @objc private func zoomOut() { setZoomIndex(currentZoomIndex - 1) }
    @objc private func resetZoom() {
        if let i = zoomLevels.firstIndex(of: 1.0) { setZoomIndex(i) }
    }

    private func setZoomIndex(_ idx: Int) {
        let clamped = max(0, min(zoomLevels.count - 1, idx))
        currentZoomIndex = clamped
        let zoom = zoomLevels[clamped]
        webView.pageZoom = zoom
        zoomLabel.stringValue = "\(Int(zoom * 100))%"
        zoomOutButton.isEnabled = clamped > 0
        zoomInButton.isEnabled = clamped < zoomLevels.count - 1
    }
}
