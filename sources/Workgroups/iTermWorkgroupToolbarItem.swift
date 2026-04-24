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
enum iTermWorkgroupToolbarItem: Codable, Equatable, Hashable {
    case gitStatus
    case changedFileSelector
    case modeSwitcher
    case back
    case forward
    case reload
    case settings
    case spacer(minWidth: CGFloat, maxWidth: CGFloat)

    // Stable identifier used for persistence and UI list keys. Never change an
    // existing rawValue — that would silently drop saved items on decode.
    var kind: String {
        switch self {
        case .gitStatus: return "gitStatus"
        case .changedFileSelector: return "changedFileSelector"
        case .modeSwitcher: return "modeSwitcher"
        case .back: return "back"
        case .forward: return "forward"
        case .reload: return "reload"
        case .settings: return "settings"
        case .spacer: return "spacer"
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
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "gitStatus": self = .gitStatus
        case "changedFileSelector": self = .changedFileSelector
        case "modeSwitcher": self = .modeSwitcher
        case "back": self = .back
        case "forward": self = .forward
        case "reload": self = .reload
        case "settings": self = .settings
        case "spacer":
            let minWidth = try c.decode(CGFloat.self, forKey: .minWidth)
            let maxWidth = try c.decode(CGFloat.self, forKey: .maxWidth)
            self = .spacer(minWidth: minWidth, maxWidth: maxWidth)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: c,
                debugDescription: "Unknown toolbar item kind: \(kind)")
        }
    }
}
