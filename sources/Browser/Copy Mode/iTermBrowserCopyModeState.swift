//
//  iTermBrowserCopyModeState.swift
//  iTerm2
//
//  Created by George Nachman on 7/29/25.
//

import Foundation
import WebKit

class iTermBrowserCopyModeState: NSObject {
    let webView: WKWebView
    private let sessionSecret: String
    private var continuation: CheckedContinuation<Bool, Never>?

    var selecting: Bool = false {
        didSet {
            webView.evaluateJavaScript("iTerm2CopyMode.selecting = \(selecting)",
                                       in: nil,
                                       in: .defaultClient,
                                       completionHandler: nil)
        }
    }
    var mode: iTermSelectionMode = .kiTermSelectionModeCharacter {
        didSet {
            webView.evaluateJavaScript("iTerm2CopyMode.mode = \(mode.rawValue)",
                                       in: nil,
                                       in: .defaultClient,
                                       completionHandler: nil)
        }
    }

    init(webView: WKWebView, sessionSecret: String) {
        self.webView = webView
        self.sessionSecret = sessionSecret
    }
    
    private func callJavaScriptSync(_ script: String) -> Bool {
        let c = continuation
        continuation = nil
        webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { evalResult in
            switch evalResult {
            case .success(let response):
                if let boolResponse = response as? Bool {
                    c?.resume(with: .success(boolResponse))
                } else {
                    c?.resume(with: .success(true))
                }
            case .failure(let error):
                DLog("\(error) from \(script)")
                c?.resume(with: .success(false))
            }
        }
        return true
    }
}

extension iTermBrowserCopyModeState: iTermCopyModeStateProtocol {
    func moveBackwardWord() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.moveBackwardWord('\(sessionSecret)')")
    }

    func moveForwardWord() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.moveForwardWord('\(sessionSecret)')")
    }

    func moveBackwardBigWord() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.moveBackwardBigWord('\(sessionSecret)')")
    }

    func moveForwardBigWord() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.moveForwardBigWord('\(sessionSecret)')")
    }

    func moveLeft() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.moveLeft('\(sessionSecret)')")
    }

    func moveRight() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.moveRight('\(sessionSecret)')")
    }

    func moveUp() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.moveUp('\(sessionSecret)')")
    }

    func moveDown() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.moveDown('\(sessionSecret)')")
    }

    func moveToStartOfNextLine() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.moveToStartOfNextLine('\(sessionSecret)')")
    }

    func pageUp() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.pageUp('\(sessionSecret)')")
    }

    func pageDown() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.pageDown('\(sessionSecret)')")
    }

    func pageUpHalfScreen() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.pageUpHalfScreen('\(sessionSecret)')")
    }

    func pageDownHalfScreen() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.pageDownHalfScreen('\(sessionSecret)')")
    }

    func previousMark() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.previousMark('\(sessionSecret)')")
    }

    func nextMark() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.nextMark('\(sessionSecret)')")
    }

    func moveToStart() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.moveToStart('\(sessionSecret)')")
    }

    func moveToEnd() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.moveToEnd('\(sessionSecret)')")
    }

    func moveToStartOfIndentation() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.moveToStartOfIndentation('\(sessionSecret)')")
    }

    func moveToBottomOfVisibleArea() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.moveToBottomOfVisibleArea('\(sessionSecret)')")
    }

    func moveToMiddleOfVisibleArea() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.moveToMiddleOfVisibleArea('\(sessionSecret)')")
    }

    func moveToTopOfVisibleArea() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.moveToTopOfVisibleArea('\(sessionSecret)')")
    }

    func moveToStartOfLine() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.moveToStartOfLine('\(sessionSecret)')")
    }

    func moveToEndOfLine() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.moveToEndOfLine('\(sessionSecret)')")
    }

    func swap() {
        _ = callJavaScriptSync("iTerm2CopyMode.swap('\(sessionSecret)')")
    }

    func scrollUp() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.scrollUp('\(sessionSecret)')")
    }

    func scrollDown() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.scrollDown('\(sessionSecret)')")
    }

    func performAsynchronously(_ block: (() -> Void)!, completion: ((Bool) -> Void)!) {
        Task { @MainActor in
            let result = await withCheckedContinuation { @MainActor continuation in
                self.continuation = continuation
                block()
                if self.continuation != nil {
                    self.continuation = nil
                    continuation.resume(with: .success(false))
                }
            }
            completion(result)
        }
    }
}

// MARK: - Additional Helper Methods
extension iTermBrowserCopyModeState {
    func enableCopyMode() {
        webView.evaluateJavaScript("iTerm2CopyMode.enable('\(sessionSecret)')",
                                   in: nil,
                                   in: .defaultClient,
                                   completionHandler: nil)
    }
    
    func disableCopyMode() {
        webView.evaluateJavaScript("iTerm2CopyMode.disable('\(sessionSecret)')",
                                   in: nil,
                                   in: .defaultClient,
                                   completionHandler: nil)
    }
    
    func copySelection() -> Bool {
        return callJavaScriptSync("iTerm2CopyMode.copySelection('\(sessionSecret)')")
    }
    
    func scrollCursorIntoView() {
        webView.evaluateJavaScript("iTerm2CopyMode.scrollCursorIntoView('\(sessionSecret)')",
                                   in: nil,
                                   in: .defaultClient,
                                   completionHandler: nil)
    }
}
