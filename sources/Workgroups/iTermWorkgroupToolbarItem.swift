//
//  iTermWorkgroupToolbarItem.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/23/26.
//

import CoreGraphics
import Foundation

// One toolbar tool in a workgroup session's toolbar. Using an enum with
// associated values lets each tool carry its own parameters (a spacer has
// width bounds; other tools are parameter-less today). New tools are added
// by extending this enum and registering a factory in
// iTermWorkgroupToolbarItemRegistry.
// Stable type tag for each toolbar item case. rawValue doubles as the
// JSON discriminator — never rename an existing case's rawValue or
// saved workgroups will drop that item on decode.
enum iTermWorkgroupToolbarItemKind: String, Codable, CaseIterable {
    case gitStatus
    case changedFileSelector
    case modeSwitcher
    // Bundled back / forward / reload buttons. Rendered as a single
    // toolbar item with no internal divider so the controls read as
    // a navigation cluster rather than three loose buttons. Only
    // meaningful paired with .changedFileSelector — back/forward
    // step through the diff list — so the settings UI hides this
    // option from sessions without a changed-file selector.
    case navigation
    // Stand-alone reload button. For sessions that want a "rerun"
    // affordance without back/forward (e.g. .codeReview peers, where
    // reload re-shows the prompt overlay).
    case reload
    case spacer
    // Combo box that picks the git base ref against which the
    // changedFileSelector's diff command runs. Defaults to HEAD;
    // remembers previously used values across launches. Like
    // navigation, only meaningful paired with .changedFileSelector,
    // so the settings UI hides it from sessions without one.
    case gitBaseSelector
    // On/off toggle, defaulting off, for .codeReview peers. When on,
    // the review session's clippings are sent to the workgroup's main
    // session each time the review session goes idle. The settings UI
    // only offers this item on sessions whose mode is .codeReview.
    case autoSendClippingsWhenIdle
    // On/off toggle, defaulting off, for the main (root) session. When
    // on, a code review is auto-requested from the workgroup's sole
    // code-review session each time the main session goes idle. Disabled
    // unless the workgroup has exactly one code-review session. The
    // settings UI only offers this item on root sessions.
    case autoRequestReviewWhenIdle
    // Auto-injected at runtime — never user-addable, never written to
    // disk. The decoder still understands it so a future change that
    // does persist it wouldn't trip an old client.
    case name
}

enum iTermWorkgroupToolbarItem: Codable, Equatable, Hashable {
    case gitStatus
    case changedFileSelector
    case modeSwitcher
    // Bundled back/forward/reload buttons. Each sub-button can carry
    // its own optional keyboard shortcut. Defaults are seeded by
    // iTermWorkgroupToolbarItemRegistry when the item is added; the
    // user can clear or change them in the session detail UI.
    case navigation(WorkgroupNavigationShortcuts)
    // Stand-alone reload button with an optional shortcut.
    case reload(WorkgroupToolbarShortcut?)
    case spacer(minWidth: CGFloat, maxWidth: CGFloat)
    case gitBaseSelector
    case autoSendClippingsWhenIdle
    case autoRequestReviewWhenIdle
    case name

    var kind: iTermWorkgroupToolbarItemKind {
        switch self {
        case .gitStatus: return .gitStatus
        case .changedFileSelector: return .changedFileSelector
        case .modeSwitcher: return .modeSwitcher
        case .navigation: return .navigation
        case .reload: return .reload
        case .spacer: return .spacer
        case .gitBaseSelector: return .gitBaseSelector
        case .autoSendClippingsWhenIdle: return .autoSendClippingsWhenIdle
        case .autoRequestReviewWhenIdle: return .autoRequestReviewWhenIdle
        case .name: return .name
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case minWidth
        case maxWidth
        case backShortcut
        case forwardShortcut
        case reloadShortcut
        case shortcut
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        switch self {
        case .spacer(let minWidth, let maxWidth):
            try c.encode(minWidth, forKey: .minWidth)
            try c.encode(maxWidth, forKey: .maxWidth)
        case .navigation(let shortcuts):
            try c.encodeIfPresent(shortcuts.back, forKey: .backShortcut)
            try c.encodeIfPresent(shortcuts.forward, forKey: .forwardShortcut)
            try c.encodeIfPresent(shortcuts.reload, forKey: .reloadShortcut)
        case .reload(let shortcut):
            try c.encodeIfPresent(shortcut, forKey: .shortcut)
        case .gitStatus, .changedFileSelector, .modeSwitcher,
             .gitBaseSelector, .autoSendClippingsWhenIdle,
             .autoRequestReviewWhenIdle, .name:
            break
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(iTermWorkgroupToolbarItemKind.self,
                                forKey: .kind)
        switch kind {
        case .gitStatus: self = .gitStatus
        case .changedFileSelector: self = .changedFileSelector
        case .modeSwitcher: self = .modeSwitcher
        case .navigation:
            // Older configs stored navigation with no shortcut keys —
            // missing fields decode as nil so the user gets an unbound
            // shortcut rather than the default. The registry's
            // defaultValue seeds defaults on freshly-added items.
            let back = try c.decodeIfPresent(
                WorkgroupToolbarShortcut.self, forKey: .backShortcut)
            let forward = try c.decodeIfPresent(
                WorkgroupToolbarShortcut.self, forKey: .forwardShortcut)
            let reload = try c.decodeIfPresent(
                WorkgroupToolbarShortcut.self, forKey: .reloadShortcut)
            self = .navigation(WorkgroupNavigationShortcuts(
                back: back, forward: forward, reload: reload))
        case .reload:
            let shortcut = try c.decodeIfPresent(
                WorkgroupToolbarShortcut.self, forKey: .shortcut)
            self = .reload(shortcut)
        case .spacer:
            let minWidth = try c.decode(CGFloat.self, forKey: .minWidth)
            let maxWidth = try c.decode(CGFloat.self, forKey: .maxWidth)
            self = .spacer(minWidth: minWidth, maxWidth: maxWidth)
        case .gitBaseSelector: self = .gitBaseSelector
        case .autoSendClippingsWhenIdle: self = .autoSendClippingsWhenIdle
        case .autoRequestReviewWhenIdle: self = .autoRequestReviewWhenIdle
        case .name: self = .name
        }
    }
}
