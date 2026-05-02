//
//  iTermWorkgroupSessionConfig.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/23/26.
//

import Foundation

//                             ┌──────────────────────────┐
//                             │ iTermWorkgroupController │ (singleton)
//                             ├──────────────────────────┤
//                             │ instances ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌│───[String:iTermWorkgroupInstance]
//                             └──────────────────────────┘                *   (one per active workgroup,
//                                                                         │    keyed by leader's ObjectIdentifier)
//                                                                         ▼
//     ┌────────────────────┐             ┌────────────────────────────────────┐
//     │ iTermWorkgroup     │             │ iTermWorkgroupInstance             │
//     │ (config snapshot)  │             ├────────────────────────────────────┤
//     ├────────────────────┤<────────────│╌workgroup                          │
//  ┌─*│╌╌╌sessions         │     ┌╴╴╴╴╴╴╴│╌mainSession                        │
//  │  │   name             │     ╵       │ peerPort ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌│──────┐
//  │  │   uniqueIdentifier │     ╵       │ nestedPeerPorts ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌│*─────┤
//  │  └────────────────────┘     ╵       │ gitPoller ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌│──┐   │
//  │                             ╵       │ nonPeerEntriesByConfigID ╌╌╌╌╌╌╌╌╌╌│──│───│─>[String:NonPeerEntry]
//  │                             ╵       │ trackedSessionIdentities (Set)     │  │   │              *
//  │                             ╵       │ gitDirectoryTracker ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌│──│───│──┐           │
//  │                             ╵       └────────────────────────────────────┘  │   │  │           ▼
//  │                             ╵                 ▲                             │   │  │   ┌──────────────┐
//  │                             ▼                 ╵                             │   │  │   │ NonPeerEntry │
//  │                     ┌─────────────────────┐   ╵                             │   │  │   ├──────────────┤
//  │                     │ PTYSession          │<──╵─────────────────────────────│───│──│───│╌session      │
//  │                     ├─────────────────────┤   ╵             ┌───────────────│───│──│──*│╌items        │
//  │                     │ workgroupInstance ……│╴╴╴┘             │               │   │  │   └──────────────┘
//  │              ┌─────>│ peerPort ╌╌╌╌╌╌╌╌╌╌╌│╴╴┐              │               │   │  │
//  │              │      └─────────────────────┘  ╵              │               │   │  │
//  │              │                               ▼              │               │   │  │
//  │              │              ┌────────────────────────┐      │               │   │  │
//  │              │              │ PTYSessionPeerPort     │      │               │   │  │
//  │              │              ├────────────────────────┤      │               │   │  │
//  │      Promise<PTYSession>───*│╌peers                  │      │               │   │  │
//  │                             │ activeSessionIdentifier│      │               │   │  │
//  │                             │ leader                 │      │               │   │  │
//  │                             └────────────────────────┘      │               │   │  │
//  │                                          ▲                  │               │   │  │
//  │                                          ║                  │               │   │  │
//  │                             ┌────────────────────────┐      │               │   │  │
//  │                             │ iTermWorkgroupPeerPort │<─────│───────────────────┘  │
//  │                             ├────────────────────────┤      │               │      │
//  │  ┌─────────────────────────*│╌peerConfigs            │      │               │      │
//  │  │                       ┌──│╌itemsByPeerID          │      │               │      │
//  │  │                       │  └────────────────────────┘      │               │      │
//  │  │                       ▼                                  │               │      │
//  │  │ [String:[SessionToolbarGenericView]]                     │               │      │
//  │  │                       *                                  ▼               │      │
//  │  │                       │          ┌──────────────────────────┐            │      │
//  │  │                       │          │ SessionToolbarGenericView│            │      │
//  │  │                       └─────────>└──────────────────────────┘            │      │
//  │  │                                               ▲                          │      │
//  │  │   ┌──────────────────────────────┐            ║                          │      │
//  │  └──>│ iTermWorkgroupSessionConfig  │   ┌──────────────────┐                │      │
//  └─────>├──────────────────────────────┤   │ SessionToolbar…  │                │      │
//         │ uniqueIdentifier             │   └──────────────────┘                │      │
//         │ parentID                     │                                       │      │
//         │ kind                         │                                       │      │
//         │ profileGUID                  │                                       │      │
//         │ command                      │                                       │      │
//         │ perFileCommand               │                                       │      │
//         │ urlString                    │                                       │      │
//         │ toolbarItems ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌│*─>[enum iTermWorkgroupToolbarItem]    │      │
//         │ displayName                  │                                       │      │
//         └──────────────────────────────┘                                       │      │
//                                                    ┌────────────────┐          │      │
//                                        ┌──────────>│ iTermGitPoller │<─────────┘      │
//                                        │           └────────────────┘                 │
//                                        │                                              │
//                                        │                                              │
//                          ┌─────────────────────┐   ┌───────────────────┐              │
//                          │ iTermGitStringMaker │<──│ iTermAutoGitString│<─────────────┘
//                          └─────────────────────┘   └───────────────────┘


// One node in a workgroup's session tree. The tree shape is encoded by
// parentID — this struct deliberately doesn't hold children, because an
// NSOutlineView datasource needs to traverse by parent lookup anyway and
// decoupling storage from traversal keeps mutations trivial.
//
// Whether this session is a terminal or a browser is decided by the
// profile, not by the workgroup; we store `command` and `urlString` as
// independent fields and the runtime consumes whichever is appropriate
// for the resolved profile.
struct iTermWorkgroupSessionConfig: Codable, Equatable {
    let uniqueIdentifier: String
    var parentID: String?
    var kind: Kind
    var profileGUID: String?
    var command: String
    // Optional command template for the changedFileSelector toolbar
    // item. When the user picks a file from the selector, the peer
    // gets Ctrl-C'd and this command is run with `\(file)` substituted
    // for the picked path. Only meaningful when this session's toolbar
    // contains .changedFileSelector; ignored otherwise.
    var perFileCommand: String
    var urlString: String
    var toolbarItems: [iTermWorkgroupToolbarItem]
    // Label shown for this session in a peer-mode switcher. Required
    // (non-empty) when the session's kind is .peer; optional otherwise
    // (falls back to a kind-specific default). Lives at the session
    // level, not inside .peer's associated value, so a session that is
    // both a split AND a peer-group host/member can carry a name.
    var displayName: String
    // Behavioral mode applied when the session is launched. .regular
    // is the historical behavior (run the command immediately).
    // .codeReview shows an in-session prompt overlay and defers the
    // program start until the user clicks Start; the entered text is
    // exposed as the variable `codeReviewPrompt` for swifty-string
    // interpolation in `command`.
    var mode: iTermWorkgroupSessionMode

    private enum CodingKeys: String, CodingKey {
        case uniqueIdentifier
        case parentID
        case kind
        case profileGUID
        case command
        case perFileCommand
        case urlString
        case toolbarItems
        case displayName
        case mode
    }

    init(uniqueIdentifier: String,
         parentID: String?,
         kind: Kind,
         profileGUID: String?,
         command: String,
         urlString: String,
         toolbarItems: [iTermWorkgroupToolbarItem],
         displayName: String = "",
         perFileCommand: String = "",
         mode: iTermWorkgroupSessionMode = .regular) {
        self.uniqueIdentifier = uniqueIdentifier
        self.parentID = parentID
        self.kind = kind
        self.profileGUID = profileGUID
        self.command = command
        self.perFileCommand = perFileCommand
        self.urlString = urlString
        self.toolbarItems = toolbarItems
        self.displayName = displayName
        self.mode = mode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uniqueIdentifier = try c.decode(String.self, forKey: .uniqueIdentifier)
        parentID = try c.decodeIfPresent(String.self, forKey: .parentID)
        kind = try c.decode(Kind.self, forKey: .kind)
        profileGUID = try c.decodeIfPresent(String.self, forKey: .profileGUID)
        command = try c.decode(String.self, forKey: .command)
        perFileCommand =
            (try? c.decode(String.self, forKey: .perFileCommand)) ?? ""
        urlString = try c.decode(String.self, forKey: .urlString)
        toolbarItems = try c.decode([iTermWorkgroupToolbarItem].self,
                                    forKey: .toolbarItems)
        displayName =
            (try? c.decode(String.self, forKey: .displayName)) ?? ""
        mode =
            (try? c.decode(iTermWorkgroupSessionMode.self, forKey: .mode)) ?? .regular
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

extension iTermWorkgroupSessionConfig {
    // POSIX shell-escape: wrap in single quotes, expanding any
    // embedded single quote to the four-char '\'' sequence. Used
    // for both `\(file)` and `\(gitBase)` substitution so the
    // shell can never interpret user-typed text as
    // metacharacters — even though git refs and filenames
    // generally don't carry shell metas, the gitBase value comes
    // from a free-form combo box and a paste of `;rm -rf ~` would
    // otherwise execute when interpolated raw.
    private static func shellSingleQuoted(_ s: String) -> String {
        return "'"
            + s.replacingOccurrences(of: "'", with: "'\\''")
            + "'"
    }

    // Render `perFileCommand` with the picked filename substituted
    // for the `\(file)` placeholder and `\(gitBase)` substituted
    // with the current git base ref (defaults to "HEAD"). Both
    // placeholders are shell-escaped; existing templates that
    // already quote them (e.g. `… -- '\(file)'`) still work —
    // the result becomes `''escaped''`, which is shell-equivalent
    // to the just-quoted string.
    func resolvedPerFileCommand(filename: String,
                                gitBase: String = CCGitBaseSelectorItem.defaultBase) -> String {
        return perFileCommand
            .replacingOccurrences(of: "\\(file)",
                                  with: Self.shellSingleQuoted(filename))
            .replacingOccurrences(of: "\\(gitBase)",
                                  with: Self.shellSingleQuoted(gitBase))
    }

    // Substitute `\(gitBase)` in `command`. Used at workgroup-entry
    // spawn time and on diffDidSelectAllFiles restarts. Same shell-
    // escape contract as resolvedPerFileCommand.
    func resolvedCommand(gitBase: String = CCGitBaseSelectorItem.defaultBase) -> String {
        return command.replacingOccurrences(
            of: "\\(gitBase)",
            with: Self.shellSingleQuoted(gitBase))
    }

    // Returns a copy with `\(gitBase)` substituted in `command`.
    // Used to pre-resolve at spawn time so the spawner's downstream
    // (non-swifty) launch path doesn't hand the shell a literal
    // backslash-paren. The codeReview path is unaffected: its
    // template still has `\(gitBase)` available in the `command`
    // field, but evaluator runs against the leader scope which we
    // also set, so the result is the same value.
    func substitutingGitBase(_ gitBase: String) -> iTermWorkgroupSessionConfig {
        var copy = self
        copy.command = copy.resolvedCommand(gitBase: gitBase)
        return copy
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
