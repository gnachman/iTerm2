//
//  TmuxWorkgroupState.swift
//  iTerm2SharedARC
//
//  A workgroup in a tmux Integration tab keeps its state on the tmux server so that every attached
//  iTerm2 agrees about it:
//    - Session option @iterm2_wg_<hex of instance ID>: the workgroup's shape and the instance's
//      git base (InstanceRecord). The shape is a skeleton of kinds and modes. Commands, names,
//      profiles and toolbars are never stored: they may be private, and they legitimately differ
//      between Macs. An attaching iTerm2 takes all behavior from its own workgroup whose skeleton
//      is equal.
//    - Pane option @iterm2_wg on every member pane: instance ID and the member's position in a
//      pre-order walk of the skeleton (PaneTag). Pane options travel with the pane through
//      swap-pane, so switching peers rewrites nothing.
//    - Window option @iterm2_wg_parked on each hidden window holding a parked peer (ParkedTag).
//      A parked peer has a window of its own, pinned to the size of the slot it occupies when shown,
//      so it runs at its real size while hidden and switching does not resize it.
//  Which peer is visible is derived from where the panes are, never stored. This file is the pure
//  part: encoding, decoding, deriving instances from what tmux reports, and matching a local
//  workgroup.
//
//  Anything read from tmux may be attacker-controlled: a control sequence in untrusted output can
//  put iTerm2 into tmux Integration mode against a fake server, and what iTerm2 then sends is typed
//  into a real shell. So, as with @tab_colors and @it2_client_*, every value is a one-letter prefix,
//  an underscore and lowercase hex of versioned JSON, the variable part of an option name is hex,
//  and nothing decoded from tmux is ever sent back except re-encoded this way. A stored skeleton
//  can only select among the user's own workgroups.
//

import Foundation

enum TmuxWorkgroupState {
    static let paneOptionName = "@iterm2_wg"
    static let parkedOptionName = "@iterm2_wg_parked"
    private static let instanceOptionPrefix = "@iterm2_wg_"
    static let currentVersion = 1

    static func instanceOptionName(instanceID: String) -> String {
        return instanceOptionPrefix + hexEncoded(Data(instanceID.utf8))
    }

    /// The instance ID named by a session option, or nil if it is not an instance option.
    static func instanceID(fromOptionName name: String) -> String? {
        guard name.hasPrefix(instanceOptionPrefix),
              let data = hexDecoded(String(name.dropFirst(instanceOptionPrefix.count))) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Encoding

    static func hexEncoded(_ data: Data) -> String {
        return (data as NSData).it_hexEncoded()
    }

    /// Strict: non-empty, even length, lowercase hex digits only.
    static func hexDecoded(_ string: String) -> Data? {
        guard !string.isEmpty,
              string.utf8.count % 2 == 0,
              string.utf8.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }) else {
            return nil
        }
        return (string as NSString).dataFromHexValues()
    }

    static func encode<T: Encodable>(_ value: T, prefix: String) -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            return prefix + hexEncoded(try encoder.encode(value))
        } catch {
            it_fatalError("Failed to encode \(T.self): \(error)")
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from encoded: String, prefix: String) -> T? {
        guard encoded.hasPrefix(prefix),
              let json = hexDecoded(String(encoded.dropFirst(prefix.count))) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: json)
    }

    // MARK: - Skeleton

    /// A workgroup's shape: a tree of kinds and modes with children in definition order. Two
    /// workgroups with equal skeletons have members that correspond one-to-one by position.
    struct Skeleton: Codable, Equatable {
        static let maximumDepth = 16
        static let maximumNodeCount = 128

        enum Kind: String, Codable {
            case root, peer, split, tab
        }

        struct Node: Codable, Equatable {
            var kind: Kind
            var mode: iTermWorkgroupSessionMode
            var children: [Node]

            private enum CodingKeys: String, CodingKey {
                case kind = "k"
                case mode = "m"
                case children = "c"
            }

            init(kind: Kind, mode: iTermWorkgroupSessionMode, children: [Node]) {
                self.kind = kind
                self.mode = mode
                self.children = children
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                kind = try container.decode(Kind.self, forKey: .kind)
                mode = try container.decode(iTermWorkgroupSessionMode.self, forKey: .mode)
                children = try container.decodeIfPresent([Node].self, forKey: .children) ?? []
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(kind, forKey: .kind)
                try container.encode(mode, forKey: .mode)
                if !children.isEmpty {
                    try container.encode(children, forKey: .children)
                }
            }
        }

        /// A host and its peers, by position. The host comes first.
        struct PeerGroupShape: Equatable {
            var host: Int
            var members: [Int]
        }

        var root: Node

        init?(root: Node) {
            self.root = root
            guard isValid else {
                return nil
            }
        }

        /// Nil if the workgroup breaks its invariants (exactly one root, every other member's parent
        /// exists, no cycles, unique IDs) or the skeleton rules. Such a workgroup never matches.
        init?(workgroup: iTermWorkgroup) {
            guard let (root, _) = Self.walk(workgroup) else {
                return nil
            }
            self.init(root: root)
        }

        init(from decoder: Decoder) throws {
            let root = try decoder.singleValueContainer().decode(Node.self)
            guard let skeleton = Skeleton(root: root) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "Invalid workgroup skeleton"))
            }
            self = skeleton
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(root)
        }

        /// Config IDs of a workgroup's members, indexed by position.
        static func configIDsByPosition(in workgroup: iTermWorkgroup) -> [String]? {
            guard let (root, ids) = walk(workgroup), Skeleton(root: root) != nil else {
                return nil
            }
            return ids
        }

        /// Nodes in pre-order: index is position.
        var nodes: [Node] {
            var result = [Node]()
            func visit(_ node: Node) {
                result.append(node)
                node.children.forEach(visit)
            }
            visit(root)
            return result
        }

        /// One group per non-peer node with peer children, in position order of the host.
        var peerGroups: [PeerGroupShape] {
            var result = [PeerGroupShape]()
            var next = 0
            func visit(_ node: Node) {
                let position = next
                next += 1
                var peers = [Int]()
                for child in node.children {
                    if child.kind == .peer {
                        peers.append(next)
                    }
                    visit(child)
                }
                if !peers.isEmpty {
                    result.append(PeerGroupShape(host: position, members: [position] + peers))
                }
            }
            visit(root)
            return result.sorted { $0.host < $1.host }
        }

        // Rules shared by stored and local skeletons: only the top node is the root, peers do not
        // host peers, and the size is bounded.
        private var isValid: Bool {
            var count = 0
            func valid(_ node: Node, depth: Int, isTop: Bool) -> Bool {
                count += 1
                guard depth <= Self.maximumDepth,
                      count <= Self.maximumNodeCount,
                      (node.kind == .root) == isTop,
                      !(node.kind == .peer && node.children.contains { $0.kind == .peer }) else {
                    return false
                }
                return node.children.allSatisfy { valid($0, depth: depth + 1, isTop: false) }
            }
            return valid(root, depth: 1, isTop: true)
        }

        // Builds the tree from the flat list, children grouped by parentID in list order, and the
        // config IDs in pre-order.
        private static func walk(_ workgroup: iTermWorkgroup) -> (Node, [String])? {
            let sessions = workgroup.sessions
            guard Set(sessions.map(\.uniqueIdentifier)).count == sessions.count,
                  sessions.count <= maximumNodeCount else {
                return nil
            }
            let tops = sessions.filter { $0.parentID == nil }
            guard tops.count == 1, let top = tops.first else {
                return nil
            }
            var childrenByParent = [String: [iTermWorkgroupSessionConfig]]()
            for session in sessions {
                if let parentID = session.parentID {
                    childrenByParent[parentID, default: []].append(session)
                }
            }
            var ids = [String]()
            func build(_ config: iTermWorkgroupSessionConfig, depth: Int) -> Node? {
                guard depth <= maximumDepth else {
                    return nil
                }
                ids.append(config.uniqueIdentifier)
                var children = [Node]()
                for child in childrenByParent[config.uniqueIdentifier] ?? [] {
                    guard let node = build(child, depth: depth + 1) else {
                        return nil
                    }
                    children.append(node)
                }
                return Node(kind: Kind(config.kind), mode: config.mode, children: children)
            }
            // Members unreachable from the root (a missing parent or a cycle) leave ids short.
            guard let root = build(top, depth: 1), ids.count == sessions.count else {
                return nil
            }
            return (root, ids)
        }
    }

    // MARK: - Encoded values

    /// The value of @iterm2_wg_<hex of instance ID>: "g_<hex of JSON>".
    struct InstanceRecord: Codable, Equatable {
        private static let prefix = "g_"

        private var version: Int
        /// The uniqueIdentifier of the workgroup it was entered from. Only a hint for choosing among
        /// several local workgroups with the same skeleton.
        var workgroupID: String
        var gitBase: String
        var skeleton: Skeleton

        private enum CodingKeys: String, CodingKey {
            case version = "v"
            case workgroupID = "wg"
            case gitBase = "base"
            case skeleton = "skel"
        }

        init(workgroupID: String, gitBase: String, skeleton: Skeleton) {
            self.version = TmuxWorkgroupState.currentVersion
            self.workgroupID = workgroupID
            self.gitBase = gitBase
            self.skeleton = skeleton
        }

        var encoded: String {
            return TmuxWorkgroupState.encode(self, prefix: Self.prefix)
        }

        /// Nil for garbage, hand edits, invalid skeletons, and versions other than ours (another
        /// client's newer format).
        init?(encoded: String) {
            guard let record = TmuxWorkgroupState.decode(Self.self, from: encoded, prefix: Self.prefix),
                  record.version == TmuxWorkgroupState.currentVersion else {
                return nil
            }
            self = record
        }
    }

    /// Whether a member in this mode runs nothing until it is started: a code review when the user
    /// starts it, a diff when there are changes to show.
    static func startsWaiting(_ mode: iTermWorkgroupSessionMode) -> Bool {
        switch mode {
        case .codeReview, .diff:
            return true
        case .regular:
            return false
        }
    }

    /// The value of @iterm2_wg on a member pane: "m_<hex of JSON>".
    struct PaneTag: Equatable {
        private static let prefix = "m_"

        private struct Wire: Codable {
            var v: Int
            var i: String
            var n: Int
            /// Omitted when false, so a started member's tag is what it was before this existed.
            var w: Bool?
        }

        var instanceID: String
        /// Index in a pre-order walk of the instance's skeleton.
        var position: Int
        /// The member's program has not started (see startsWaiting). Every attached client shows it
        /// as waiting, and whichever starts it clears this.
        var waiting: Bool

        init(instanceID: String, position: Int, waiting: Bool = false) {
            self.instanceID = instanceID
            self.position = position
            self.waiting = waiting
        }

        /// This tag once the member has started.
        var started: PaneTag {
            return PaneTag(instanceID: instanceID, position: position)
        }

        var encoded: String {
            return TmuxWorkgroupState.encode(Wire(v: TmuxWorkgroupState.currentVersion, i: instanceID, n: position,
                                                  w: waiting ? true : nil),
                                             prefix: Self.prefix)
        }

        init?(encoded: String) {
            guard let wire = TmuxWorkgroupState.decode(Wire.self, from: encoded, prefix: Self.prefix),
                  wire.v == TmuxWorkgroupState.currentVersion,
                  !wire.i.isEmpty,
                  wire.n >= 0 else {
                return nil
            }
            self.init(instanceID: wire.i, position: wire.n, waiting: wire.w ?? false)
        }
    }

    /// The value of @iterm2_wg_parked on a window holding one of an instance's parked peers:
    /// "p_<hex of JSON>".
    struct ParkedTag: Equatable {
        private static let prefix = "p_"

        private struct Wire: Codable {
            var v: Int
            var i: String
        }

        var instanceID: String

        init(instanceID: String) {
            self.instanceID = instanceID
        }

        var encoded: String {
            return TmuxWorkgroupState.encode(Wire(v: TmuxWorkgroupState.currentVersion, i: instanceID),
                                             prefix: Self.prefix)
        }

        init?(encoded: String) {
            guard let wire = TmuxWorkgroupState.decode(Wire.self, from: encoded, prefix: Self.prefix),
                  wire.v == TmuxWorkgroupState.currentVersion,
                  !wire.i.isEmpty else {
                return nil
            }
            self.init(instanceID: wire.i)
        }
    }

    // MARK: - Matching a local workgroup

    enum Match: Equatable {
        case unique(iTermWorkgroup)
        /// Several local workgroups have the shape and none is the one it was entered from: the
        /// user picks among these.
        case ambiguous([iTermWorkgroup])
        /// No local workgroup has the shape: the user picks any, or installs a preset first.
        case noMatch
    }

    static func match(_ record: InstanceRecord, among workgroups: [iTermWorkgroup]) -> Match {
        let candidates = workgroups.filter { Skeleton(workgroup: $0) == record.skeleton }
        if candidates.count == 1, let only = candidates.first {
            return .unique(only)
        }
        if let same = candidates.first(where: { $0.uniqueIdentifier == record.workgroupID }) {
            return .unique(same)
        }
        return candidates.isEmpty ? .noMatch : .ambiguous(candidates)
    }

    // MARK: - What tmux reports

    struct PaneSize: Equatable {
        var width: Int
        var height: Int
    }

    struct Pane: Equatable {
        var paneID: Int
        var windowID: Int
        /// The raw value of @iterm2_wg, if set.
        var tag: String?
        var size: PaneSize?

        init(paneID: Int, windowID: Int, tag: String?, size: PaneSize? = nil) {
            self.paneID = paneID
            self.windowID = windowID
            self.tag = tag
            self.size = size
        }
    }

    struct Window: Equatable {
        var windowID: Int
        /// The raw value of @iterm2_wg_parked, if set.
        var parkedTag: String?
    }

    // MARK: - Derived

    enum Problem: Equatable {
        /// A second pane claims a member already claimed by a lower pane ID. It is not a member.
        case duplicateMember(position: Int, paneID: Int)
        /// A pane's tag names a position the skeleton does not have. It is not a member.
        case unknownPosition(paneID: Int, position: Int)
        /// No pane is the root: the instance has ended.
        case leaderMissing
        /// Peers of a group in view besides the visible one (e.g. a client died
        /// mid-switch). They should be parked again.
        case extraVisiblePeers(host: Int, positions: [Int])
        /// Every present member of a group is parked. The host should be brought back.
        case noVisiblePeer(host: Int)
        /// A pane in one of this instance's parked windows that is not one of its parked peers. It
        /// would be invisible forever, so it should be brought out into a tab.
        case strandedInParkedWindow(paneID: Int)
    }

    /// A host and its peers, by position, as they are now.
    struct PeerGroup: Equatable {
        var host: Int
        /// The host first, then its peers in definition order.
        var members: [Int]
        /// The member in view: the host if it is in view, else the first member in view.
        var visible: Int?
        /// Present members in parked windows, in member order.
        var hidden: [Int]
    }

    /// A parked peer's window to pin to a new size.
    struct Resize: Equatable {
        var paneID: Int
        var size: PaneSize
    }

    struct Instance: Equatable {
        var instanceID: String
        var record: InstanceRecord
        /// Windows tagged as parked for this instance, sorted.
        var parkedWindowIDs: [Int]
        var paneForPosition: [Int: Int]
        /// Sizes of the members' panes, where tmux reported them.
        var sizeForPosition: [Int: PaneSize]
        var peerGroups: [PeerGroup]
        /// Positions whose members have not started (PaneTag.waiting).
        var waitingPositions: Set<Int> = []
        /// Non-root positions with no pane (e.g. a code review peer not started yet), in position
        /// order. These are created on demand, not repaired.
        var missingPositions: [Int]
        /// In order: duplicate and unknown members by pane ID, then
        /// leaderMissing, then visibility by host, then stranded panes by pane ID.
        var problems: [Problem]
    }

    struct Derivation: Equatable {
        /// Sorted by instance ID.
        var instances: [Instance]
        /// Panes tagged for an instance with no record. A member is never tagged before its record
        /// exists, so these are left by a removal that was interrupted. An orphan member should be
        /// killed; an orphan leader (the user's own shell) only untagged.
        var orphanLeaderPaneIDs: [Int]
        var orphanMemberPaneIDs: [Int]
        /// Instances whose record cannot be read (e.g. another client's newer format). Left alone,
        /// never torn down. Their panes are not orphans.
        var undecodableInstanceIDs: [String]
    }

    private struct TaggedPane {
        var paneID: Int
        var windowID: Int
        var position: Int
        var size: PaneSize?
        var waiting: Bool
    }

    /// - Parameter instanceOptions: Raw instance option values keyed by instance ID.
    static func derive(panes: [Pane],
                       windows: [Window],
                       instanceOptions: [String: String]) -> Derivation {
        var records = [String: InstanceRecord]()
        var undecodable = [String]()
        for (instanceID, value) in instanceOptions {
            if let record = InstanceRecord(encoded: value) {
                records[instanceID] = record
            } else {
                undecodable.append(instanceID)
            }
        }

        let sortedPanes = panes.sorted { $0.paneID < $1.paneID }
        var panesByInstance = [String: [TaggedPane]]()
        var orphanLeaders = [Int]()
        var orphanMembers = [Int]()
        for pane in sortedPanes {
            guard let raw = pane.tag, let tag = PaneTag(encoded: raw) else {
                continue
            }
            if instanceOptions[tag.instanceID] == nil {
                if tag.position == 0 {
                    orphanLeaders.append(pane.paneID)
                } else {
                    orphanMembers.append(pane.paneID)
                }
            } else {
                panesByInstance[tag.instanceID, default: []].append(
                    TaggedPane(paneID: pane.paneID, windowID: pane.windowID, position: tag.position, size: pane.size,
                               waiting: tag.waiting))
            }
        }

        var parkedByInstance = [String: [Int]]()
        for window in windows.sorted(by: { $0.windowID < $1.windowID }) {
            if let raw = window.parkedTag, let tag = ParkedTag(encoded: raw) {
                parkedByInstance[tag.instanceID, default: []].append(window.windowID)
            }
        }

        let instances = records.keys.sorted().map { instanceID in
            let parkedWindowIDs = parkedByInstance[instanceID] ?? []
            let othersParkedWindowIDs = Set(parkedByInstance.filter { $0.key != instanceID }.values.joined())
            return deriveInstance(instanceID: instanceID,
                                  record: records[instanceID]!,
                                  panes: panesByInstance[instanceID] ?? [],
                                  parkedWindowIDs: parkedWindowIDs,
                                  othersParkedWindowIDs: othersParkedWindowIDs,
                                  paneIDsInParkedWindows: sortedPanes.filter {
                                      parkedWindowIDs.contains($0.windowID)
                                  }.map(\.paneID))
        }
        return Derivation(instances: instances,
                          orphanLeaderPaneIDs: orphanLeaders,
                          orphanMemberPaneIDs: orphanMembers,
                          undecodableInstanceIDs: undecodable.sorted())
    }

    private static func deriveInstance(instanceID: String,
                                       record: InstanceRecord,
                                       panes: [TaggedPane],
                                       parkedWindowIDs: [Int],
                                       othersParkedWindowIDs: Set<Int>,
                                       paneIDsInParkedWindows: [Int]) -> Instance {
        let skeleton = record.skeleton
        let nodeCount = skeleton.nodes.count
        let shapes = skeleton.peerGroups
        var problems = [Problem]()

        // panes is sorted by pane ID, so the lower pane ID wins a duplicate.
        var paneForPosition = [Int: Int]()
        var windowForPosition = [Int: Int]()
        var sizeForPosition = [Int: PaneSize]()
        var waitingPositions = Set<Int>()
        for pane in panes {
            if pane.position >= nodeCount {
                problems.append(.unknownPosition(paneID: pane.paneID, position: pane.position))
            } else if paneForPosition[pane.position] != nil {
                problems.append(.duplicateMember(position: pane.position, paneID: pane.paneID))
            } else {
                paneForPosition[pane.position] = pane.paneID
                windowForPosition[pane.position] = pane.windowID
                sizeForPosition[pane.position] = pane.size
                if pane.waiting {
                    waitingPositions.insert(pane.position)
                }
            }
        }

        if paneForPosition[0] == nil {
            problems.append(.leaderMissing)
        }

        let isHidden = { (position: Int) -> Bool in
            windowForPosition[position].map { parkedWindowIDs.contains($0) } ?? false
        }
        // A member in another instance's parked window is hidden from the user but not parked for
        // this instance: it is stranded, and neither visible nor hidden here.
        let isInAnothersParkedWindow = { (position: Int) -> Bool in
            windowForPosition[position].map { othersParkedWindowIDs.contains($0) } ?? false
        }
        let peerGroups = shapes.map { shape -> PeerGroup in
            let present = shape.members.filter { paneForPosition[$0] != nil && !isInAnothersParkedWindow($0) }
            let shown = present.filter { !isHidden($0) }
            let visible = shown.contains(shape.host) ? shape.host : shown.first
            if let visible {
                let extras = shown.filter { $0 != visible }
                if !extras.isEmpty {
                    problems.append(.extraVisiblePeers(host: shape.host, positions: extras))
                }
            } else if !present.isEmpty {
                problems.append(.noVisiblePeer(host: shape.host))
            }
            return PeerGroup(host: shape.host,
                             members: shape.members,
                             visible: visible,
                             hidden: present.filter(isHidden))
        }

        let parkedPaneIDs = Set(shapes.flatMap(\.members).compactMap { paneForPosition[$0] })
        var stranded = paneIDsInParkedWindows.filter { !parkedPaneIDs.contains($0) }
        stranded += paneForPosition.keys.filter(isInAnothersParkedWindow).compactMap { paneForPosition[$0] }
        for paneID in Set(stranded).sorted() {
            problems.append(.strandedInParkedWindow(paneID: paneID))
        }

        return Instance(instanceID: instanceID,
                        record: record,
                        parkedWindowIDs: parkedWindowIDs,
                        paneForPosition: paneForPosition,
                        sizeForPosition: sizeForPosition,
                        peerGroups: peerGroups,
                        waitingPositions: waitingPositions,
                        missingPositions: (1..<max(nodeCount, 1)).filter { paneForPosition[$0] == nil },
                        problems: problems)
    }
}

private extension TmuxWorkgroupState.Skeleton.Kind {
    init(_ kind: iTermWorkgroupSessionConfig.Kind) {
        switch kind {
        case .root:
            self = .root
        case .peer:
            self = .peer
        case .split:
            self = .split
        case .tab:
            self = .tab
        }
    }
}

extension TmuxWorkgroupState.Instance {
    /// Parked peers whose size differs from the slot they fill when shown, which is wherever their
    /// group's visible member is (TmuxWorkgroupCommands.createParkedPeer pins them to it). The slot
    /// changes size when the user resizes the window.
    var parkedPeersToResize: [TmuxWorkgroupState.Resize] {
        return peerGroups.flatMap { group -> [TmuxWorkgroupState.Resize] in
            guard let slot = group.visible.flatMap({ sizeForPosition[$0] }) else {
                return []
            }
            return group.hidden.compactMap { position in
                guard let paneID = paneForPosition[position], sizeForPosition[position] != slot else {
                    return nil
                }
                return TmuxWorkgroupState.Resize(paneID: paneID, size: slot)
            }
        }
    }
}
