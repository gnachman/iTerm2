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
        let rules = iTermProfilePreferences.object(forKey: KEY_SMART_SELECTION_RULES, inProfile: profile) as? [[String: Any]] ?? SmartSelectionController.defaultRules() ?? []
        return rules.map { dict in
            return SmartSelectRule(regex: SmartSelectionController.regex(inRule: dict),
                                   weight: SmartSelectionController.precision(inRule: dict),
                                   actions: SmartSelectionController.actions(inRule: dict) ?? [])
        }
    }
    
    func browserViewController(_ controller: iTermBrowserViewController, didHoverURL url: String?, frame: NSRect) {
        let webView = controller.webView
        let frameInSessionView = view.convert(frame, from: webView)
        _ = view.setHoverURL(url, anchorFrame: frameInSessionView)
    }

    func browserViewController(_ controller: iTermBrowserViewController,
                               didNavigateTo url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        currentHost = VT100RemoteHost(username: components?.user, hostname: url.host)
    }

    func browserViewControllerDidBecomeFirstResponder(_ controller: iTermBrowserViewController) {
        notifyActive()
    }

    func browserViewController(_ controller: iTermBrowserViewController, didCopyString string: String) {
        PasteboardHistory.sharedInstance().save(string)
    }

    func browserViewController(_ controller: iTermBrowserViewController, runCommand command: String) {
        guard iTermWarning.show(withTitle: "OK to run:\n\(command)",
                             actions: ["OK", "Cancel"],
                             accessory: nil,
                             identifier: nil,
                             silenceable: .kiTermWarningTypePersistent,
                             heading: "Run command?",
                                window: view.window) == .kiTermWarningSelection0 else {
            return
        }
        iTermController.sharedInstance().openSingleUseWindow(withCommand: command,
                                                             inject: nil,
                                                             environment: nil,
                                                             pwd: nil,
                                                             options: [.doNotEscapeArguments],
                                                             didMakeSession: nil,
                                                             completion: nil)
    }

    func browserViewControllerScope(_ controller: iTermBrowserViewController) -> (iTermVariableScope, iTermObject) {
        return (genericScope, self)
    }

    func browserViewControllerShouldInterpolateSmartSelectionParameters(_ controller: iTermBrowserViewController) -> Bool {
        return iTermProfilePreferences.bool(forKey: KEY_SMART_SELECTION_ACTIONS_USE_INTERPOLATED_STRINGS,
                                            inProfile: profile)
    }

    func browserViewController(_ controller: iTermBrowserViewController, openFile file: String) {
        guard iTermWarning.show(withTitle: "OK to open this file?\n\(file)",
                             actions: ["OK", "Cancel"],
                             accessory: nil,
                             identifier: nil,
                             silenceable: .kiTermWarningTypePersistent,
                             heading: "Open file?",
                                window: view.window) == .kiTermWarningSelection0 else {
            return
        }
        NSWorkspace.shared.openFile(file)
    }

    func browserViewController(_ controller: iTermBrowserViewController, performSplitPaneAction action: iTermBrowserSplitPaneAction) {
        switch action {
        case .splitPaneVertically, .splitPaneHorizontally:
            textViewSplitVertically(action == .splitPaneVertically, withProfileGuid: nil)

        case .movePane:
            textViewMovePane()

        case .moveBrowserToTab:
            if let window = view.window {
                MovePaneController.sharedInstance().moveSession(self, toTabIn: window)
            }

        case .moveBrowserToWindow:
            if let window = view.window {
                MovePaneController.sharedInstance().moveSession(toNewWindow: self,
                                                                at: window.convertPoint(toScreen: NSPoint(x: -10.0, y: -10.0)))
            }
        case .swapSessions:
            MovePaneController.sharedInstance().swapPane(self)
        }
    }

    func browserViewControllerCurrentTabHasMultipleSessions(_ controller: iTermBrowserViewController) -> Bool {
        return (delegate?.sessions().count ?? 0) > 1
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
