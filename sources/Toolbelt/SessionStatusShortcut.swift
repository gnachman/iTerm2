//
//  SessionStatusShortcut.swift
//  iTerm2SharedARC
//

import Foundation

/// The keyboard shortcut label identifying a session in the Session Status
/// UIs. Extracted from ToolStatus so the toolbelt tool and the status bar
/// component label a row identically. The two differ only in which session
/// counts as "active" — the toolbelt's current session versus the session
/// hosting the status bar — so that is the sole parameter.
enum SessionStatusShortcut {
    // Mirrors WorkgroupModeSwitcherItem's segment labels: a peer with a
    // configured custom peerSwitchShortcut shows that shortcut; otherwise
    // peers 1..8 get their numeric digit, the *last* peer gets ⌥⇧⌘9
    // (which is what activatePeer(byShortcutDigit: 9) does), and peers
    // between 9 and count-1 get nothing.
    static func peerSwitchShortcutLabel(port: iTermWorkgroupPeerPort,
                                        peerID: String) -> String? {
        if let custom = port.customShortcutLabel(forPeerID: peerID) {
            return custom
        }
        let position = port.position(forPeerID: peerID)
        guard position > 0 else {
            return nil
        }
        if position <= 8 {
            return "⌥⇧⌘\(position)"
        }
        if position == port.peerCount {
            return "⌥⇧⌘9"
        }
        return nil
    }

    static func shortcutString(for sessionID: String,
                               activeSessionGUID: String?) -> String? {
        guard let controller = iTermController.sharedInstance() else {
            return nil
        }
        guard let session = controller.anySession(withGUID: sessionID) else {
            return nil
        }

        // Peer-of-focus sessions get their ⌥⇧⌘<digit> peer-switch
        // shortcut, which always wins over pane/tab shortcuts: the
        // user wants the keystroke that switches *the focused pane*
        // to this peer, not the keystroke that focuses some other
        // split. This also applies to the row for the currently
        // active peer — the shortcut still identifies which peer the
        // row represents (and pressing it is a harmless no-op).
        // Non-visible peers are reached via anySession(withGUID:)'s
        // peer-port fallback; their delegate may not match this tab
        // but their peerPort reference survives.
        if let activeGUID = activeSessionGUID,
           let activeSession = controller.anySession(withGUID: activeGUID),
           let activePort = activeSession.peerPort as? iTermWorkgroupPeerPort,
           activePort.contains(session: session),
           let peerID = activePort.identifier(for: session),
           let label = peerSwitchShortcutLabel(port: activePort, peerID: peerID) {
            return label
        }

        // For pane/tab shortcuts we need a session that's actually in
        // a tab. If `session` itself isn't (e.g. it's a non-visible
        // workgroup peer of some other pane), use its port's active
        // peer instead — that's the in-tab representative of the
        // group, and clicking the row activates this peer into that
        // pane, so "Pane N" of the active peer is the right shortcut.
        let visible: PTYSession
        if controller.terminal(with: session) != nil {
            visible = session
        } else if let activePeer = session.peerPort?.activeSession,
                  controller.terminal(with: activePeer) != nil {
            visible = activePeer
        } else {
            return nil
        }
        guard let terminal = controller.terminal(with: visible) else {
            return nil
        }
        guard let sessionTab = visible.delegate as? PTYTab else {
            return nil
        }
        let currentTab = terminal.currentTab()

        if sessionTab === currentTab && sessionTab.sessions().count > 1 {
            // Session (or its in-tab peer) is in the current tab —
            // show pane shortcut.
            let ordinal = visible.view?.ordinal ?? 0
            if ordinal != 0 {
                let paneTag = iTermPreferencesModifierTag(
                    rawValue: iTermPreferences.int(forKey: kPreferenceKeySwitchPaneModifier))
                if let paneTag, paneTag.rawValue != iTermPreferencesModifierTag.preferenceModifierTagNone.rawValue {
                    let mask = iTermPreferences.mask(for: paneTag)
                    let modString = NSString.modifierSymbols(mask: mask)
                    return "\(modString)\(ordinal)"
                }
                return "Pane \(ordinal)"
            }
        }
        // Session is in a different tab — show tab shortcut
        let tabIndex = Int(terminal.index(of: sessionTab)) + 1  // 0-based to 1-based
        if tabIndex < 1 || tabIndex > 9 {
            return nil
        }
        guard let tabTag = iTermPreferencesModifierTag(
            rawValue: iTermPreferences.int(forKey: kPreferenceKeySwitchTabModifier)) else {
            return nil
        }
        if tabTag.rawValue == iTermPreferencesModifierTag.preferenceModifierTagNone.rawValue {
            return "Tab \(tabIndex)"
        }
        let mask = iTermPreferences.mask(for: tabTag)
        let modString = NSString.modifierSymbols(mask: mask)
        return "\(modString)\(tabIndex)"
    }
}
