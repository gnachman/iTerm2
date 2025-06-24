//
//  PTYSession+Browser.swift
//  iTerm2
//
//  Created by George Nachman on 6/19/25.
//

import Foundation
import WebKit

@available(macOS 11.0, *)
extension PTYSession: iTermBrowserViewControllerDelegate {
    func browserViewController(_ controller: iTermBrowserViewController, didUpdateTitle title: String?) {
        if let title {
            setUntrustedIconName(title)
        }
    }
    
    func browserViewController(_ controller: iTermBrowserViewController, didUpdateFavicon favicon: NSImage?) {
        if let favicon {
            delegate?.sessionDidChangeGraphic(self, shouldShow: true, image: favicon)
        }
    }
    
    func browserViewController(_ controller: iTermBrowserViewController,
                               requestNewWindowForURL url: URL,
                               configuration: WKWebViewConfiguration) -> WKWebView? {
        let openTargetBlankInWindow = false
        if openTargetBlankInWindow {
            return iTermController.sharedInstance().openSingleUserBrowserWindow(with: url,
                                                                                configuration: configuration,
                                                                                options: [],
                                                                                completion: {})
        } else {
            let term = (delegate?.realParentWindow() as? PseudoTerminal)
            return term?.openTab(with: url,
                                 baseProfile: profile,
                                 nearSessionGuid: guid,
                                 configuration: configuration)
        }
    }

    func browserViewController(_ controller: iTermBrowserViewController,
                               openNewTabForURL url: URL) {
        let term = (delegate?.realParentWindow() as? PseudoTerminal)
        term?.openTab(with: url,
                      baseProfile: profile,
                      nearSessionGuid: guid,
                      configuration: nil)
    }

    func browserViewController(_ controller: iTermBrowserViewController,
                               openNewSplitPaneForURL url: URL,
                               vertical: Bool) {
        let term = (delegate?.realParentWindow() as? PseudoTerminal)
        term?.openSplitPane(with: url,
                            baseProfile: profile,
                            nearSessionGuid: guid,
                            vertical: vertical)
    }

    func browserViewControllerShowFindPanel(_ controller: iTermBrowserViewController) {
        // Route to SessionView's find infrastructure
        userInitiatedShowFindPanel()
    }

    func browserViewController(_ controller: iTermBrowserViewController,
                               openPasswordManagerForHost host: String?,
                               forUser: Bool,
                               didSendUserName: (() -> ())?) {
        if let itad = NSApp.delegate as? iTermApplicationDelegate{
            itad.openPasswordManager(
                toAccountName: host,
                in: self,
                forUser: forUser,
                didSendUserName: didSendUserName)
        }
    }

    func browserViewControllerDidSelectAskAI(_ controller: iTermBrowserViewController,
                                             title: String,
                                             content: String) {
        guard let windowController = ChatWindowController.instance(showErrors: true) else {
            return
        }
        windowController.showChatWindow()
        windowController.createChat(name: title, inject: content)
    }
}

// MARK: - Browser Find Support

@available(macOS 13.0, *)
extension PTYSession {
    @objc func browserFindString(_ aString: String,
                                forwardDirection direction: Bool,
                                mode: iTermFindMode,
                                withOffset offset: Int,
                                scrollToFirstResult: Bool,
                                force: Bool) {
        guard let vc = view.browserViewController else {
            return
        }
        
        // For browser mode, we ignore offset parameter since WKWebView doesn't support it.
        // force parameter indicates whether to start new search or continue with next/previous.
        
        if force || aString != vc.activeSearchTerm {
            // Start new search (force=true or different search string)
            let caseSensitive = (mode == .caseSensitiveSubstring || mode == .caseSensitiveRegex)
            vc.startFind(aString, caseSensitive: caseSensitive)
        } else {
            // Continue existing search (move to next/previous result)
            if direction {
                vc.findNext(nil)
            } else {
                vc.findPrevious(nil)
            }
        }
    }
}
