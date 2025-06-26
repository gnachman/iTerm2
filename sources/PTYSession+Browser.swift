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

    func browserViewControllerSetMouseInfo(_ controller: iTermBrowserViewController,
                                           pointInView: NSPoint,
                                           button: Int,
                                           count: Int,
                                           modifiers: NSEvent.ModifierFlags,
                                           sideEffects: iTermClickSideEffects,
                                           state: iTermMouseState) {
        textViewSetClick(
            VT100GridAbsCoord(x: Int32(clamping: pointInView.x),
                              y: Int64(clamping: pointInView.y)),
            button: button,
            count: count,
            modifiers: modifiers,
            sideEffects: sideEffects,
            state: state)
    }

    func browserViewControllerMovePane(_ controller: iTermBrowserViewController) {
        MovePaneController.sharedInstance().movePane(self)
    }

    func browserViewControllerEnclosingTerminal(_ controller: iTermBrowserViewController) -> PseudoTerminal? {
        return delegate?.realParentWindow() as? PseudoTerminal
    }

    func browserViewControllerSplit(_ controller: iTermBrowserViewController, vertically: Bool, guid: String) {
        textViewSplitVertically(vertically, withProfileGuid: guid)
    }

    func browserViewControllerSelectPane(_ controller: iTermBrowserViewController, forward: Bool) {
        if forward {
            delegate?.nextSession()
        } else {
            delegate?.previousSession()
        }
    }

    func browserViewControllerInvoke(_ controller: iTermBrowserViewController, scriptFunction: String) {
        invokeFunctionCall(scriptFunction,
                           scope: genericScope,
                           origin: "Pointer action")
    }

    func browserViewControllerSmartSelectionRules(_ controller: iTermBrowserViewController) -> [SmartSelectRule] {
        (textview.smartSelectionRules ?? SmartSelectionController.defaultRules()).compactMap { obj -> SmartSelectRule? in
            guard let dict = obj as? [AnyHashable: Any] else {
                return nil
            }
            return SmartSelectRule(regex: SmartSelectionController.regex(inRule: dict),
                                   weight: SmartSelectionController.precision(inRule: dict))
        }
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
