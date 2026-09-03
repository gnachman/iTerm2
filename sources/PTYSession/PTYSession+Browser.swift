//
//  PTYSession+Browser.swift
//  iTerm2
//
//  Created by George Nachman on 6/19/25.
//

import Foundation
import WebKit

extension PTYSession: iTermBrowserViewControllerDelegate {
    func browserFindManager(_ manager: iTermBrowserFindManager, didUpdateResult result: iTermBrowserFindResultBundle) {
        view?.findDriver?.viewController.countDidChange()
    }

    // True if the session already has a non-blank auto name (seeded from the profile
    // name, or restored from a saved arrangement's last page title).
    var hasExistingSessionName: Bool {
        let existing = (genericScope.value(forVariableName: iTermVariableKeySessionAutoNameFormat) as? String) ?? ""
        return !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var browserProfileDisplayName: String {
        profile?[KEY_NAME] as? String ?? iTermBrowserSessionTitle.defaultProfileName
    }

    func browserViewController(_ controller: iTermBrowserViewController, didUpdateTitle title: String?) {
        // A browser session has no job, so route the page title through the session name.
        // The session-name title component is guaranteed for browsers by
        // iTermSessionTitleBuiltInFunction, so this is what renders in the tab and
        // per-pane title bars. A blank title mid-load is transient (WebKit fires it at
        // didCommit before the new <title> is parsed), so we keep the current name to
        // avoid flicker; the host/profile fallback for a genuinely titleless page is
        // applied once the page settles in browserViewControllerDidFinishNavigation.
        if let name = iTermBrowserSessionTitle.resolvedName(pageTitle: title,
                                                            host: nil,
                                                            profileName: browserProfileDisplayName,
                                                            navigationSettled: false) {
            DLog("browserTitle: using page title \(name)")
            setUntrustedIconName(name)
        } else {
            DLog("browserTitle: transient blank page title; keeping current name")
        }
        // A session restored from a saved arrangement caches its (empty) title from
        // before the name was known and does not always recompute when the variable
        // changes, so force a re-evaluation now that the name is set.
        nameController.setNeedsUpdate()
    }

    func browserViewController(_ controller: iTermBrowserViewController, didUpdateFavicon favicon: NSImage?) {
        if let favicon {
            delegate?.sessionDidChangeGraphic(self, shouldShow: true, image: favicon)
        }
    }

    func browserViewController(_ controller: iTermBrowserViewController, didUpdateBackgroundColor color: NSColor?) {
        // Feeds the page's background color into the session so the minimal theme's
        // light/dark decision (and tab tint) tracks the actual page instead of the
        // profile's static terminal background. Propagation is rate limited in the
        // setter because it triggers a relayout and appearance recompute.
        browserBackgroundColor = color
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
        let baseProfile = ProfileModel.profileForCreatingNewSessionBased(on: profile)
        return term?.openTab(with: url,
                             baseProfile: baseProfile,
                             nearSessionGuid: guid,
                             configuration: configuration)
    }

    func browserViewController(_ controller: iTermBrowserViewController,
                               openNewTabForURL url: URL) {
        let term = (delegate?.realParentWindow() as? PseudoTerminal)
        let baseProfile = ProfileModel.profileForCreatingNewSessionBased(on: profile)
        term?.openTab(with: url,
                      baseProfile: baseProfile,
                      nearSessionGuid: guid,
                      configuration: nil)
    }

    func browserViewController(_ controller: iTermBrowserViewController,
                               openNewSplitPaneForURL url: URL,
                               vertical: Bool) {
        let term = (delegate?.realParentWindow() as? PseudoTerminal)
        let baseProfile = ProfileModel.profileForCreatingNewSessionBased(on: profile)
        term?.openSplitPane(with: url,
                            target: nil,
                            baseProfile: baseProfile,
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
        let rules = iTermProfilePreferences.object(forKey: KEY_SMART_SELECTION_RULES, inProfile: justProfile) as? [[String: Any]] ?? SmartSelectionController.defaultRules() ?? []
        return rules.map { dict in
            return SmartSelectRule(regex: SmartSelectionController.regex(inRule: dict),
                                   weight: SmartSelectionController.precision(inRule: dict),
                                   actions: SmartSelectionController.actions(inRule: dict) ?? [])
        }
    }

    func browserViewController(_ controller: iTermBrowserViewController, didHoverURL url: String?, frame: NSRect) {
        guard let view else { return }
        let webView = controller.webView
        let frameInSessionView = view.convert(frame, from: webView)
        _ = view.setHoverURL(url, anchorFrame: frameInSessionView)
    }
    
    func browserViewControllerOnboardingEnableAdBlocker(_ controller: iTermBrowserViewController) {
        // Enable ad blocking globally
        iTermAdvancedSettingsModel.setWebKitAdblockEnabled(true)
        RLog("Ad blocking enabled from onboarding")
    }
    
    func browserViewControllerOnboardingEnableInstantReplay(_ controller: iTermBrowserViewController) {
        // Update in my profile (which may be divorced)
        let guid = justProfile[KEY_GUID]! as! String
        let model = isDivorced ? ProfileModel.sessionsInstance()! : ProfileModel.sharedInstance()!
        let mutator = iTermProfilePreferenceMutator(model: model, guid: guid)
        mutator.set(key: KEY_INSTANT_REPLAY, value: true)

        // If I am divorced also update the original profile
        if let originalGuid = justProfile[KEY_ORIGINAL_GUID] as? String {
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
            KEY_NAME: iTermBrowserSessionTitle.defaultProfileName,
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
        let origGuid = justProfile[KEY_GUID] as! String
        ProfileModel.sessionsInstance().setProfilePreservingGuidWithGuid(origGuid,
                                                                         fromProfile: newProfile,
                                                                         overrides: [:])
    }
    
    func browserViewControllerOnboardingCheckBrowserProfileExists(_ controller: iTermBrowserViewController) -> Bool {
        return ProfileModel.sharedInstance().bookmarks().anySatisfies({ ($0 as NSDictionary).profileIsBrowser })
    }
    
    func browserViewControllerOnboardingFindBrowserProfileGuid(_ controller: iTermBrowserViewController) -> String? {
        // First check if the current session's profile is a browser profile
        if let currentGuid = justProfile[KEY_GUID] as? String,
           let currentProfile = ProfileModel.sharedInstance().bookmark(withGuid: currentGuid) as? NSDictionary,
           currentProfile.profileIsBrowser {
            return currentGuid
        }

        // If divorced, check the original profile
        if let originalGuid = justProfile[KEY_ORIGINAL_GUID] as? String,
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
        let instantReplayEnabled = iTermProfilePreferences.bool(forKey: KEY_INSTANT_REPLAY, inProfile: justProfile)
        
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
        guard iTermWarning.show(withTitle: String(format: String(localized: "PtySessionBrowser_OkToRunN_FORMAT", defaultValue: "OK to run:\n%1$@", comment: "Alert title in browserViewController"), command),
                                actions: [String(localized: "COMMON_OK", defaultValue: "OK", comment: "Action title in browserViewController"), String(localized: "COMMON_CANCEL", defaultValue: "Cancel", comment: "Action title in browserViewController")],
                                accessory: nil,
                                identifier: nil,
                                silenceable: .kiTermWarningTypePersistent,
                                heading: String(localized: "PtySessionBrowser_RunCommand", defaultValue: "Run command?", comment: "Alert heading in browserViewController"),
                                window: view?.window) == .kiTermWarningSelection0 else {
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

    // The browser view controller is hosted by this PTYSession, so the
    // owning session is just self. Used by the workgroup browser
    // triggers, which need a PTYSession to enter/exit a workgroup on.
    func browserViewControllerSession(_ controller: iTermBrowserViewController) -> PTYSession? {
        return self
    }

    func browserViewControllerShouldInterpolateSmartSelectionParameters(_ controller: iTermBrowserViewController) -> Bool {
        return iTermProfilePreferences.bool(forKey: KEY_SMART_SELECTION_ACTIONS_USE_INTERPOLATED_STRINGS,
                                            inProfile: justProfile)
    }

    func browserViewController(_ controller: iTermBrowserViewController, openFile file: String) {
        guard iTermWarning.show(withTitle: String(format: String(localized: "PtySessionBrowser_OkToOpenThisFileN_FORMAT", defaultValue: "OK to open this file?\n%1$@", comment: "Alert title in browserViewController"), file),
                                actions: [String(localized: "COMMON_OK", defaultValue: "OK", comment: "Action title in browserViewController"), String(localized: "COMMON_CANCEL", defaultValue: "Cancel", comment: "Action title in browserViewController")],
                                accessory: nil,
                                identifier: nil,
                                silenceable: .kiTermWarningTypePersistent,
                                heading: String(localized: "PtySessionBrowser_OpenFile", defaultValue: "Open file?", comment: "Alert heading in browserViewController"),
                                window: view?.window) == .kiTermWarningSelection0 else {
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
            MovePaneController.sharedInstance().moveSession(toTab: self)

        case .moveBrowserToWindow:
            if let window = view?.window {
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
        // The page has settled. If it finished loading with no <title>, fall back to the
        // host (then the profile name) instead of keeping the previous page's title.
        if let name = iTermBrowserSessionTitle.resolvedName(pageTitle: controller.title,
                                                            host: controller.currentURL?.host,
                                                            profileName: browserProfileDisplayName,
                                                            navigationSettled: true) {
            setUntrustedIconName(name)
            nameController.setNeedsUpdate()
        }
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
            return session.view?.browserViewController?.webView
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
            if let announcement {
                queueAnnouncement(announcement, identifier: request.identifier)
            } else {
                continuation.resume(returning: nil)
            }
        }
    }

    func browserViewController(_ controller: iTermBrowserViewController,
                               handleKeyDown event: NSEvent) -> Bool {
        if view?.currentAnnouncement?.handleKeyDown(event) == true {
            return true
        }
        return false
    }

    func browserViewControllerToggleSetting(_ controller: iTermBrowserViewController,
                                            key: String,
                                            isProfile: Bool) {
        toggleSetting(withKey: key, isProfile: isProfile)
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
        guard let vc = view?.browserViewController else {
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
        guard let vc = view?.browserViewController else {
            return
        }
        vc.resetFindCursor()
    }
    
    @objc func browserFindInProgress() -> Bool {
        guard let vc = view?.browserViewController else {
            return false
        }
        return vc.findInProgress
    }
    
    @objc func browserContinueFind(_ progress: UnsafeMutablePointer<Double>, range: NSRangePointer) -> Bool {
        guard let vc = view?.browserViewController else {
            progress.pointee = 1.0
            range.pointee = NSRange(location: 100, length: 100)
            return false
        }
        return vc.continueFind(progress: progress, range: range)
    }
    
    @objc func browserNumberOfSearchResults() -> Int {
        guard let vc = view?.browserViewController else {
            return 0
        }
        return vc.numberOfSearchResults
    }
    
    @objc func browserCurrentIndex() -> Int {
        guard let vc = view?.browserViewController else {
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
