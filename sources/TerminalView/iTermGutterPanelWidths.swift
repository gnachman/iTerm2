//
//  iTermGutterPanelWidths.swift
//  iTerm2SharedARC
//
//  Persistent, user-draggable widths for right-gutter panels, keyed by the
//  panel's stable identifier. Stored under NoSync-prefixed user-default keys
//  because a panel width is local UI state, not a synced configuration
//  setting: a user who loads prefs from a shared location (e.g. Dropbox)
//  shouldn't be prompted to write just because they dragged a gutter wider on
//  one machine.
//
//  Both a panel's `width` getter and its registered widthProvider read
//  through here so the two stay in lockstep (see iTermRightGutterPanel.h).
//

import Foundation

enum iTermGutterPanelWidths {
    // Hard backstops applied to any stored or proposed width. The drag
    // handler additionally clamps against the live window size so the
    // terminal grid is never crushed; these are the absolute limits. The
    // floor of 225 keeps panels from getting narrow enough to look broken.
    static let minWidth: CGFloat = 225
    static let maxWidth: CGFloat = 1200

    private static func key(forIdentifier identifier: String) -> String {
        return "NoSyncGutterPanelWidth_\(identifier)"
    }

    static func clamped(_ width: CGFloat) -> CGFloat {
        return min(maxWidth, max(minWidth, width))
    }

    // The persisted width for the panel, or `defaultValue` if the user has
    // never resized it. Always clamped to [minWidth, maxWidth].
    static func width(forIdentifier identifier: String, defaultValue: CGFloat) -> CGFloat {
        let defaults = iTermUserDefaults.userDefaults()
        let key = key(forIdentifier: identifier)
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return clamped(CGFloat(defaults.double(forKey: key)))
    }

    static func setWidth(_ width: CGFloat, forIdentifier identifier: String) {
        iTermUserDefaults.userDefaults().set(Double(clamped(width)),
                                             forKey: key(forIdentifier: identifier))
    }
}
