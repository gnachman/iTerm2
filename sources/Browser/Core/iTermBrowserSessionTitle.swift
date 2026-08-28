//
//  iTermBrowserSessionTitle.swift
//  iTerm2
//
//  Pure decision logic for a browser session's displayed title and for which Session
//  Title component menu items apply to a browser profile. Kept free of PTYSession /
//  WebKit so it is unit testable.
//

import Foundation

@objc(iTermBrowserSessionTitle)
final class iTermBrowserSessionTitle: NSObject {
    // The default display name for a browser session with no page title, host, or
    // configured profile name.
    @objc static let defaultProfileName = "Web Browser"

    // Returns the session name to display given a page title and context, or nil to
    // keep the current name unchanged.
    //
    // - navigationSettled: true once the page has finished loading (didFinish), so a
    //   blank title means the page genuinely has no <title> and we fall back to the
    //   host, then the profile name. false during load (WebKit fires a blank title at
    //   didCommit, before the new document's <title> is parsed), so a blank title is
    //   transient and the current name is kept to avoid flickering to the bare host.
    static func resolvedName(pageTitle: String?,
                             host: String?,
                             profileName: String,
                             navigationSettled: Bool) -> String? {
        let trimmedTitle = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        guard navigationSettled else {
            // Transient blank during load (pre-<title>-parse): keep the current name so
            // the tab doesn't flicker to the bare host on every committed navigation.
            return nil
        }
        // The page finished loading with no title, so it genuinely has none: fall back
        // to the host, then the profile name.
        if let host, !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return host
        }
        return profileName
    }

    // Title-component menu items that are meaningless for a browser session (it has no
    // job, tty, host, user, working directory, command line, or terminal size).
    static let terminalOnlyComponents: iTermTitleComponents = [
        .job, .workingDirectory, .TTY, .user, .host, .commandLine, .size
    ]

    // Whether a Session Title component menu item should be hidden for a profile.
    @objc(shouldHideTitleComponentMenuItemWithTag:isBrowser:selectedComponents:)
    static func shouldHideTitleComponentMenuItem(tag: Int,
                                                 isBrowser: Bool,
                                                 selectedComponents: UInt) -> Bool {
        guard isBrowser, tag > 0 else {
            return false
        }
        let tagComponents = iTermTitleComponents(rawValue: UInt(tag))
        if tagComponents.isDisjoint(with: terminalOnlyComponents) {
            return false  // not a terminal-only component (e.g. a name component)
        }
        // Hide terminal-only components for a browser profile UNLESS one is currently
        // selected -- a stale selection (e.g. from an older build's job-only default)
        // must stay visible so the user can turn it off.
        let selected = iTermTitleComponents(rawValue: selectedComponents)
        return tagComponents.isDisjoint(with: selected)
    }
}
