//
//  iTermWorkgroupSession.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/23/26.
//

import Foundation

// One node in a workgroup's session tree. The tree shape is encoded by
// parentID — this struct deliberately doesn't hold children, because an
// NSOutlineView datasource needs to traverse by parent lookup anyway and
// decoupling storage from traversal keeps mutations trivial.
//
// Whether this session is a terminal or a browser is decided by the
// profile, not by the workgroup; we store `command` and `urlString` as
// independent fields and the runtime consumes whichever is appropriate
// for the resolved profile.
struct iTermWorkgroupSession: Codable, Equatable {
    let uniqueIdentifier: String
    var parentID: String?
    var kind: Kind
    var profileGUID: String?
    var command: String
    var urlString: String
    var toolbarItems: [iTermWorkgroupToolbarItem]
    // Label shown for this session in a peer-mode switcher. Required
    // (non-empty) when the session's kind is .peer; optional otherwise
    // (falls back to a kind-specific default). Lives at the session
    // level, not inside .peer's associated value, so a session that is
    // both a split AND a peer-group host/member can carry a name.
    var displayName: String

    private enum CodingKeys: String, CodingKey {
        case uniqueIdentifier
        case parentID
        case kind
        case profileGUID
        case command
        case urlString
        case toolbarItems
        case displayName
    }

    init(uniqueIdentifier: String,
         parentID: String?,
         kind: Kind,
         profileGUID: String?,
         command: String,
         urlString: String,
         toolbarItems: [iTermWorkgroupToolbarItem],
         displayName: String = "") {
        self.uniqueIdentifier = uniqueIdentifier
        self.parentID = parentID
        self.kind = kind
        self.profileGUID = profileGUID
        self.command = command
        self.urlString = urlString
        self.toolbarItems = toolbarItems
        self.displayName = displayName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uniqueIdentifier = try c.decode(String.self, forKey: .uniqueIdentifier)
        parentID = try c.decodeIfPresent(String.self, forKey: .parentID)
        kind = try c.decode(Kind.self, forKey: .kind)
        profileGUID = try c.decodeIfPresent(String.self, forKey: .profileGUID)
        command = try c.decode(String.self, forKey: .command)
        urlString = try c.decode(String.self, forKey: .urlString)
        toolbarItems = try c.decode([iTermWorkgroupToolbarItem].self,
                                    forKey: .toolbarItems)
        displayName =
            (try? c.decode(String.self, forKey: .displayName)) ?? ""
    }

    enum Kind: Codable, Equatable {
        case root
        case peer
        case split(SplitSettings)
        case tab

        private enum CodingKeys: String, CodingKey { case kind, split }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .root:
                try c.encode("root", forKey: .kind)
            case .peer:
                try c.encode("peer", forKey: .kind)
            case .split(let settings):
                try c.encode("split", forKey: .kind)
                try c.encode(settings, forKey: .split)
            case .tab:
                try c.encode("tab", forKey: .kind)
            }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let k = try c.decode(String.self, forKey: .kind)
            switch k {
            case "root":
                self = .root
            case "peer":
                self = .peer
            case "split":
                self = .split(try c.decode(SplitSettings.self, forKey: .split))
            case "tab":
                self = .tab
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .kind,
                    in: c,
                    debugDescription: "Unknown session kind: \(k)")
            }
        }
    }
}

struct SplitSettings: Codable, Equatable {
    enum Orientation: String, Codable { case vertical, horizontal }

    // Which side of the parent the new pane occupies. For vertical splits
    // leadingOrTop means "left"; for horizontal splits it means "top".
    enum Side: String, Codable { case leadingOrTop, trailingOrBottom }

    var orientation: Orientation
    var side: Side
    var location: Double  // 0...1 — fraction of parent consumed by the new pane
}
