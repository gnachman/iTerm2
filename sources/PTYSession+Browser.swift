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
    func browserFindManager(_ manager: iTermBrowserFindManager, didUpdateResult result: iTermBrowserFindResultBundle) {
        view.findDriver.viewController.countDidChange()
    }

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
                               configuration: WKWebViewConfiguration) -> iTermBrowserWebView? {
        /* If you ever want to open in a window, do:
         return iTermController.sharedInstance().openSingleUserBrowserWindow(with: url,
         configuration: configuration,
         options: [],
         completion: {})
         */
        let term = (delegate?.realParentWindow() as? PseudoTerminal)
        return term?.openTab(with: url,
                             baseProfile: profile,
                             nearSessionGuid: guid,
                             configuration: configuration)
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
        windowController.createChat(name: title, inject: content, linkToBrowserSessionGuid: guid)
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
    
    func browserViewControllerOnboardingEnableAdBlocker(_ controller: iTermBrowserViewController) {
        // Enable ad blocking globally
        iTermAdvancedSettingsModel.setWebKitAdblockEnabled(true)
        DLog("Ad blocking enabled from onboarding")
    }
    
    func browserViewControllerOnboardingEnableInstantReplay(_ controller: iTermBrowserViewController) {
        // Update in my profile (which may be divorced)
        let guid = profile[KEY_GUID]! as! String
        let model = isDivorced ? ProfileModel.sessionsInstance()! : ProfileModel.sharedInstance()!
        let mutator = iTermProfilePreferenceMutator(model: model, guid: guid)
        mutator.set(key: KEY_INSTANT_REPLAY, value: true)

        // If I am divorced also update the original profile
        if let originalGuid = profile[KEY_ORIGINAL_GUID] as? String {
            let mutator = iTermProfilePreferenceMutator(model: ProfileModel.sharedInstance(),
                                                        guid: originalGuid)
            mutator.set(key: KEY_INSTANT_REPLAY, value: true)
        }
    }
    
    func browserViewControllerOnboardingCreateBrowserProfile(_ controller: iTermBrowserViewController) -> String? {
        if ProfileModel.sharedInstance().bookmarks().anySatisfies({ ($0 as NSDictionary).profileIsBrowser }) {
            DLog("Already have a browser profile")
            return nil
        }
        let guid = ProfileModel.freshGuid()!
        let dict: [AnyHashable: Any] = [
            KEY_CUSTOM_COMMAND: kProfilePreferenceCommandTypeBrowserValue,
            KEY_NAME: "Web Browser",
            KEY_GUID: guid
        ]
        ProfileModel.sharedInstance().addBookmark(dict)
        ProfileModel.sharedInstance().flush()
        NotificationCenter.default.post(name: NSNotification.Name(kReloadAllProfiles),
                                        object: nil,
                                        userInfo:nil)
        return guid
    }
    
    func browserViewControllerOnboardingSwitchToProfile(_ controller: iTermBrowserViewController,
                                                        guid: String) {
        guard let newProfile = ProfileModel.sharedInstance().bookmark(withGuid: guid) else {
            return
        }
        divorceAddressBookEntryFromPreferences()
        let origGuid = profile[KEY_GUID] as! String
        ProfileModel.sessionsInstance().setProfilePreservingGuidWithGuid(origGuid,
                                                                         fromProfile: newProfile,
                                                                         overrides: [:])
    }
    
    func browserViewControllerOnboardingCheckBrowserProfileExists(_ controller: iTermBrowserViewController) -> Bool {
        return ProfileModel.sharedInstance().bookmarks().anySatisfies({ ($0 as NSDictionary).profileIsBrowser })
    }
    
    func browserViewControllerOnboardingFindBrowserProfileGuid(_ controller: iTermBrowserViewController) -> String? {
        // First check if the current session's profile is a browser profile
        if let currentGuid = profile[KEY_GUID] as? String,
           let currentProfile = ProfileModel.sharedInstance().bookmark(withGuid: currentGuid) as? NSDictionary,
           currentProfile.profileIsBrowser {
            return currentGuid
        }
        
        // If divorced, check the original profile
        if let originalGuid = profile[KEY_ORIGINAL_GUID] as? String,
           let originalProfile = ProfileModel.sharedInstance().bookmark(withGuid: originalGuid) as? NSDictionary,
           originalProfile.profileIsBrowser {
            return originalGuid
        }
        
        // Otherwise find any browser profile
        let browserProfile = ProfileModel.sharedInstance().bookmarks().first { profile in
            (profile as NSDictionary).profileIsBrowser
        }
        return browserProfile?[KEY_GUID] as? String
    }
    
    func browserViewControllerOnboardingGetSettings(_ controller: iTermBrowserViewController) -> iTermBrowserOnboardingSettings {
        // Check if ad blocker is enabled globally
        let adBlockerEnabled = iTermAdvancedSettingsModel.webKitAdblockEnabled()
        
        // Check if instant replay is enabled for the current profile
        let instantReplayEnabled = iTermProfilePreferences.bool(forKey: KEY_INSTANT_REPLAY, inProfile: profile)
        
        return iTermBrowserOnboardingSettings(
            adBlockerEnabled: adBlockerEnabled,
            instantReplayEnabled: instantReplayEnabled
        )
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
        NSWorkspace.shared.open(URL(fileURLWithPath: file))
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

    func browserViewControllerDidStartNavigation(_ controller: iTermBrowserViewController) {
        browserIsLoading = true
        updateDisplayBecause("browser activity")
    }

    func browserViewControllerDidFinishNavigation(_ controller: iTermBrowserViewController) {
        browserIsLoading = false
        updateDisplayBecause("browser activity")
    }

    func browserViewControllerDidReceiveNamedMarkUpdate(_ controller: iTermBrowserViewController) {
        // The browser manager has already handled the update via the message handler
        // We just need to notify observers that marks have changed
        NamedMarksDidChangeNotification(sessionGuid: nil).post()
    }

    func browserViewControllerBroadcastWebViews(_ controller: iTermBrowserViewController) -> [iTermBrowserWebView] {
        let sessions = delegate?.realParentWindow()?.broadcastSessions() ?? []
        // TODO: Also broadcast to terminals
        return sessions.compactMap { (session: PTYSession) -> iTermBrowserWebView? in
            guard session.isBrowserSession(), session !== self else {
                return nil
            }
            return session.view.browserViewController?.webView
        }
    }

    func browserViewController(_ controller: iTermBrowserViewController,
                               showError message: String,
                               suppressionKey: String,
                               identifier: String) {
        self.showError(message, suppressionKey: suppressionKey, identifier: identifier)
    }

    func browserViewControllerBury(_ controller: iTermBrowserViewController) {
        bury()
    }

    func browserViewController<T>(_ controller: iTermBrowserViewController,
                                  announce request: BrowserAnnouncement<T>) async -> T? {
        if hasAnnouncement(withIdentifier: request.identifier) {
            return nil
        }
        var count = 0
        return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            dismissAnnouncement(withIdentifier: request.identifier)
            let announcement = iTermAnnouncementViewController.announcement(withTitle: request.message,
                                                                            style: request.style,
                                                                            withActions: request.options.map { $0.title }) { selection in
                if count > 0 {
                    // This is always called with -2 eventually.
                    return
                }
                switch selection {
                case -2, -1:  // Dismissed programatically or closed
                    count += 1
                    continuation.resume(returning: nil)
                default:
                    count += 1
                    continuation.resume(returning: request.options[Int(selection)].identifier)
                }
            }
            queueAnnouncement(announcement, identifier: request.identifier)
        }
    }

    func browserViewController(_ controller: iTermBrowserViewController,
                               handleKeyDown event: NSEvent) -> Bool {
        if view.currentAnnouncement?.handleKeyDown(event) == true {
            return true
        }
        return false
    }
}

// MARK: - Browser Find Support

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
            let browserMode: iTermBrowserFindMode = mode.browserFindMode(query: aString)
            vc.startFind(aString, mode: browserMode, force: force)
        } else {
            // Continue existing search (move to next/previous result)
            if direction {
                vc.findNext(nil)
            } else {
                vc.findPrevious(nil)
            }
        }
    }
    
    @objc func browserResetFindCursor() {
        guard let vc = view.browserViewController else {
            return
        }
        vc.resetFindCursor()
    }
    
    @objc func browserFindInProgress() -> Bool {
        guard let vc = view.browserViewController else {
            return false
        }
        return vc.findInProgress
    }
    
    @objc func browserContinueFind(_ progress: UnsafeMutablePointer<Double>, range: NSRangePointer) -> Bool {
        guard let vc = view.browserViewController else {
            progress.pointee = 1.0
            range.pointee = NSRange(location: 100, length: 100)
            return false
        }
        return vc.continueFind(progress: progress, range: range)
    }
    
    @objc func browserNumberOfSearchResults() -> Int {
        guard let vc = view.browserViewController else {
            return 0
        }
        return vc.numberOfSearchResults
    }
    
    @objc func browserCurrentIndex() -> Int {
        guard let vc = view.browserViewController else {
            return 0
        }
        return vc.currentIndex
    }
}

extension iTermFindMode {
    func browserFindMode(query: String) -> iTermBrowserFindMode {
        switch self {
        case .smartCaseSensitivity:
            (query.rangeOfCharacter(from: CharacterSet.uppercaseLetters) != nil) ? .caseSensitive : .caseInsensitive
        case .caseSensitiveSubstring:
                .caseSensitive
        case .caseInsensitiveSubstring:
                .caseInsensitive
        case .caseSensitiveRegex:
                .caseSensitiveRegex
        case .caseInsensitiveRegex:
                .caseInsensitiveRegex
        @unknown default:
            it_fatalError()
        }
    }
}
