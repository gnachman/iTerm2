//
//  iTermBrowserCopyModeHandler.swift
//  iTerm2
//
//  Created by George Nachman on 7/31/25.
//

import Foundation
import WebKit

@MainActor
protocol iTermBrowserCopyModeHandlerDelegate: AnyObject {
    func copyModeHandlerShowFindPanel(_ sender: iTermBrowserCopyModeHandler)
}

@MainActor
class iTermBrowserCopyModeHandler: NSObject {
    static let messageHandlerName = "iTerm2CopyMode"
    private let realHandler = iTermCopyModeHandler()
    var webView: iTermBrowserWebView?

    weak var delegate: iTermBrowserCopyModeHandlerDelegate?

    private let sessionSecret: String
    var enabled = false {
        didSet {
            if enabled == oldValue {
                return
            }
            if enabled {
                webView?.safelyEvaluateJavaScript(
                    "window.iTerm2CopyMode.enable('\(sessionSecret)');",
                    in: nil,
                    in: .defaultClient)
                realHandler.enabled = true
            } else {
                webView?.safelyEvaluateJavaScript(
                    "window.iTerm2CopyMode.disable('\(sessionSecret)');",
                    in: nil,
                    in: .defaultClient)
                if realHandler.enabled {
                    realHandler.enabled = false
                }
            }
        }
    }

    static func create() -> iTermBrowserCopyModeHandler? {
        guard let secret = String.makeSecureHexString() else {
            return nil
        }
        return iTermBrowserCopyModeHandler.init(secret: secret)
    }

    private init(secret: String) {
        self.sessionSecret = secret
        super.init()
        realHandler.delegate = self
    }

    var javascript: String {
        return iTermBrowserTemplateLoader.loadTemplate(named: "copy-mode",
                                                       type: "js",
                                                       substitutions: ["SECRET": sessionSecret])
    }

    func handle(_ event: NSEvent) {
        realHandler.handle(event)
    }

    func handle(_ event: NSEvent) async -> Bool {
        return await realHandler.handleAsyncEvent(event)
    }

    func handle(_ events: [NSEvent]) async {
        let wasEnabled = enabled
        defer {
            if enabled != wasEnabled {
                enabled = wasEnabled
            }
        }
        for event in events {
            if !enabled {
                enabled = true
            }
            _ = await handle(event)
        }
    }
}

extension iTermBrowserCopyModeHandler: iTermCopyModeHandlerDelegate {
    nonisolated func copyModeHandler(_ handler: iTermCopyModeHandler,
                                     revealCurrentLineInState state: any iTermCopyModeStateProtocol) {
        MainActor.assumeIsolated {
            webView?.safelyEvaluateJavaScript(iife("iTerm2CopyMode.scrollCursorIntoView('\(sessionSecret)');"),
                                        in: nil,
                                        in: .defaultClient)
        }
    }

    nonisolated func copyModeHandlerDidChangeEnabledState(_ handler: iTermCopyModeHandler) {
        MainActor.assumeIsolated {
            if let webView {
                webView.window?.makeFirstResponder(webView)
                if !handler.enabled {
                    enabled = false
                }
            }
        }
    }

    nonisolated func copyModeHandlerRedraw(_ handler: iTermCopyModeHandler) {
    }

    nonisolated func copyModeHandlerCreateState(_ handler: iTermCopyModeHandler) -> any iTermCopyModeStateProtocol {
        return MainActor.assumeIsolated {
            return iTermBrowserCopyModeState(webView: webView!, sessionSecret: sessionSecret)
        }
    }

    nonisolated func copyModeHandlerShowFindPanel(_ handler: iTermCopyModeHandler) {
        MainActor.assumeIsolated {
            delegate?.copyModeHandlerShowFindPanel(self)
        }
    }

    nonisolated func copyModeHandlerCopySelection(_ handler: iTermCopyModeHandler) {
        Task { @MainActor in
            do {
                _ = try await webView?.safelyCallAsyncJavaScript(
                    "await iTerm2CopyMode.copySelection('\(sessionSecret)');",
                    contentWorld: .defaultClient)
            } catch {
                DLog("\(error)")
            }
        }
    }
}
