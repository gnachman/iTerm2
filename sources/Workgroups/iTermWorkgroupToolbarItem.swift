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
    // a navigation cluster rather than three loose buttons.
    case navigation
    case spacer
    // Auto-injected at runtime — never user-addable, never written to
    // disk. The decoder still understands it so a future change that
    // does persist it wouldn't trip an old client.
    case name
}

enum iTermWorkgroupToolbarItem: Codable, Equatable, Hashable {
    case gitStatus
    case changedFileSelector
    case modeSwitcher
    case navigation
    case spacer(minWidth: CGFloat, maxWidth: CGFloat)
    case name

    var kind: iTermWorkgroupToolbarItemKind {
        switch self {
        case .gitStatus: return .gitStatus
        case .changedFileSelector: return .changedFileSelector
        case .modeSwitcher: return .modeSwitcher
        case .navigation: return .navigation
        case .spacer: return .spacer
        case .name: return .name
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case minWidth
        case maxWidth
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        if case let .spacer(minWidth, maxWidth) = self {
            try c.encode(minWidth, forKey: .minWidth)
            try c.encode(maxWidth, forKey: .maxWidth)
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
        case .navigation: self = .navigation
        case .spacer:
            let minWidth = try c.decode(CGFloat.self, forKey: .minWidth)
            let maxWidth = try c.decode(CGFloat.self, forKey: .maxWidth)
            self = .spacer(minWidth: minWidth, maxWidth: maxWidth)
        case .name: self = .name
        }
    }
}
