//
//  CodexTitleStatusAdaptor.swift
//  iTerm2SharedARC
//
//  Compatibility shim for Codex CLI. Codex (OpenAI) does not emit OSC 21337;
//  it conveys its working/idle state by prefixing the terminal title
//  (OSC 0/1/2) with a braille-spinner glyph while working and removing the
//  prefix when idle or blocked on the user. This shim watches title changes
//  for sessions whose foreground job ancestry contains `codex` and
//  synthesizes the equivalent tab status so the tab indicator dot, tab
//  subtitle, and any other consumers of iTermSessionTabStatus light up the
//  same as for OSC 21337-aware agents.
//
//  Pure decoding lives in CodexTitleStatusDecoder.swift; this file owns the
//  policy (foreground-job gate, state mapping) and delegates the actual
//  state application to iTermSessionTabStatus's synthesized-status API.
//

import Foundation

@objc(iTermCodexTitleStatusAdaptor)
final class CodexTitleStatusAdaptor: NSObject {
    @objc static let sourceName = "codex"

    /// Evaluate Codex working state for a session and update its tab status.
    /// - Parameters:
    ///   - title: the session's current window title (post-OSC 0/1/2).
    ///   - ancestorJobNames: foreground job ancestor process names (deepest first),
    ///     as collected by `iTermProcessInfo.foregroundJobAncestorNames`. Values
    ///     are argv0 strings that may be plain ("codex") or path-prefixed
    ///     ("/opt/homebrew/bin/codex"); we compare on the last path component.
    ///   - tabStatus: the session's iTermSessionTabStatus.
    /// - Returns: true iff the tab status changed.
    @objc(applyForTitle:ancestorJobNames:tabStatus:)
    @discardableResult
    static func apply(title: String?,
                      ancestorJobNames: [String]?,
                      tabStatus: iTermSessionTabStatus) -> Bool {
        let codexInForeground = (ancestorJobNames ?? []).contains { name in
            (name as NSString).lastPathComponent == "codex"
        }
        if !codexInForeground {
            // Codex isn't running here. Clear anything we previously claimed.
            return tabStatus.applySynthesizedStatus(.none, source: sourceName)
        }
        // Codex is in foreground: braille-spinner prefix => working, otherwise idle.
        // We don't try to distinguish "idle vs blocked-on-user" from the title
        // alone, because Codex's title is identical in both cases. If Codex ever
        // adds an OSC signal for "Action Required", map it to .waiting here.
        let state: iTermSessionTabStatus.SynthesizedState =
            CodexTitleStatusDecoder.isWorkingTitle(title ?? "") ? .working : .idle
        return tabStatus.applySynthesizedStatus(state, source: sourceName)
    }
}
