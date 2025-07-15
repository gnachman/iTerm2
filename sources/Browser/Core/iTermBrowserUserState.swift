//
//  iTermBrowserUserState.swift
//  iTerm2
//
//  Created by George Nachman on 7/3/25.
//

import WebExtensionsFramework
import WebKit

@objc
class iTermBrowserHiddenContainer: NSView {
    var superviewObserver: ((NSView?) -> ())?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        alphaValue = 0.0
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func viewDidMoveToSuperview() {
        superviewObserver?(superview)
    }

    override func viewDidMoveToWindow() {
        iTermLogger.instance.debug("Hidden container \(it_addressString) moved to window \(window?.description ?? "(nil)")")
    }
}


@MainActor
class iTermBrowserUserState {
    private static var _instances = [iTermBrowserUser: WeakBox<iTermBrowserUserState>]()
    private let configuration: Configuration
    let user: iTermBrowserUser
    private let logger = iTermLogger()
    private let extensionManager: iTermBrowserExtensionManagerProtocol?
    let hiddenContainer = iTermBrowserHiddenContainer()

    struct Configuration: Equatable {
        var persistentStorageDisallowed: Bool

        // Set to nil to disable extensions altogether
        var baseExtensionDirectory: URL?
    }

    init(_ configuration: Configuration, user: iTermBrowserUser) {
        logger.loggerPrefix = "[Browser] "
        #if DEBUG
        logger.verbosityLevel = .debug
        #endif
        self.user = user
        self.configuration = configuration
        if #available(macOS 14, *, *), let baseExtensionDirectory = configuration.baseExtensionDirectory {
            extensionManager = iTermBrowserExtensionManager(
                logger: logger,
                baseDirectory: baseExtensionDirectory,
                persistentStorageDisallowed: configuration.persistentStorageDisallowed,
                user: user,
                hiddenContainer: hiddenContainer)
        } else {
            extensionManager = nil
        }
    }

    deinit {
        logger.info("User state for \(user) deallocated")
    }
}

extension iTermBrowserUserState {
    @MainActor
    static func instance(for user: iTermBrowserUser, configuration: Configuration) -> iTermBrowserUserState {
        if let existing = _instances[user]?.value, existing.configuration == configuration {
            return existing
        }
        let state = iTermBrowserUserState(configuration, user: user)
        _instances[user] = .init(state)
        return state
    }

    public func registerWebView(_ webView: WKWebView, contentManager: BrowserExtensionUserContentManager) {
        Task { @MainActor in
            await extensionManager?.addWebView(webView, contentManager: contentManager)
        }
    }

    public func unregisterWebView(_ webView: WKWebView) {
        extensionManager?.removeWebView(webView)
    }
}
