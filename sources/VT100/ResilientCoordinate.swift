//
//  ResilientCoordinate.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/26/26.
//

import Foundation

@objc(iTermResilientCoordinateDataSource)
protocol ResilientCoordinateDataSource: AnyObject {
    var rcScrollbackOverflow: Int64 { get }
    var rcNumberOfLines: Int32 { get }
    var rcGuid: String { get }
    var rcWidth: Int32 { get }
}

/// IntervalTree objects that hold ResilientCoordinate / ResilientCoordinateRange fields
/// conform to this protocol so EventuallyConsistentIntervalTree's add /
/// mutate side effects (and fixUpDeserializedIntervalTree:) can bind any
/// unresolved RCs to a pool's dataSource without knowing the object's
/// internal layout.
///
/// Conformance is opt-in: classes without RCs simply don't conform and
/// the tree's `respondsToSelector:` check skips them.
@objc(iTermResilientCoordinateHolder)
protocol ResilientCoordinateHolder: AnyObject {
    /// Bind every contained unbound RC to `dataSource`. Already-bound RCs
    /// are left alone. Should be idempotent.
    @objc(bindUnresolvedResilientCoordinatesToDataSource:)
    func bindUnresolvedResilientCoordinates(to dataSource: ResilientCoordinateDataSource)

    /// Detach every contained RC from its current dataSource and
    /// rebind to `dataSource`. Used by tree migration
    /// (swapOnscreenIntervalTreeObjects) so the mark observes
    /// notifications on the destination tree's pool guid instead of
    /// the source tree's. Implementations should rebind all four
    /// RC-typed fields (promptRange / commandRange / outputStart /
    /// excludedSubranges).
    @objc(rebindResilientCoordinatesToDataSource:)
    func rebindResilientCoordinates(to dataSource: ResilientCoordinateDataSource)
}

// A coordinate that correctly describes a location and is resilient to folding, scrolling,
// and so on.
@objc(iTermResilientCoordinate)
class ResilientCoordinate: NSObject {
    fileprivate weak var dataSource: ResilientCoordinateDataSource?
    fileprivate enum Location {
        case coord(VT100GridAbsCoord)
        case fold(mark: WeakBox<FoldMark>, coord: VT100GridCoord)
        case porthole(mark: WeakBox<PortholeMark>, coord: VT100GridCoord)
        // Decoded / copied coord that hasn't been bound to a live
        // ResilientCoordinateDataSource yet. Mirrors `.unresolvedFold` /
        // `.unresolvedPorthole`: a fixup pass calls `bind(to:)` to
        // upgrade it to `.coord` and register notification observers.
        case unresolvedCoord(VT100GridAbsCoord)
        // Encoded fold/porthole whose target mark has not been registered
        // yet — typically because we decoded before the FoldMark /
        // PortholeMark in the same interval tree. The stored coord is the
        // within-region coord (same shape as `.fold` / `.porthole`).
        // resolveUnresolved(foldMarkLookup:portholeMarkLookup:) upgrades
        // these to `.fold` / `.porthole` once the target mark is available.
        case unresolvedFold(markGuid: String, coord: VT100GridCoord)
        case unresolvedPorthole(markGuid: String, coord: VT100GridCoord)
        case invalid
    }
    fileprivate var location: Location {
        didSet {
            if case .invalid = location {
                NotificationCenter.default.removeObserver(self)
            }
        }
    }

    @objc
    enum Status: Int {
        case valid
        case scrolledOff  // history was not enough
        case truncatedBelow  // tail of session was truncated, losing coord
        case inFold  // within a folded section
        case invalid  // dataSource gone, enclosing fold/porthole mark gone, or bogus x coordinate.
        case inPorthole  // Coordinate belongs to a region that was replaced with a porthole
        // Decoded fold/porthole whose target mark isn't bound yet. Calls to
        // -coord / -foldInfo / -portholeInfo return the same "not usable"
        // sentinels they return for `.inFold` / `.inPorthole`; consumers
        // should retry after a resolution pass.
        case unresolved
    }

    // Designated init for a *bound* RC: registers notification observers
    // against `dataSource.rcGuid` immediately. Use this when the caller
    // already knows which pool the RC belongs to (e.g. the mutation thread
    // building a mutation-pool RC for the progenitor).
    fileprivate init(dataSource: ResilientCoordinateDataSource, location: Location) {
        self.dataSource = dataSource
        self.location = location

        super.init()

        // Nothing a notification could do would change `.invalid` or
        // an unresolved location (they need an explicit resolution pass
        // before they're meaningful). Skip the observer dance.
        switch location {
        case .coord, .fold, .porthole:
            observeNotifications(guid: dataSource.rcGuid)
        case .invalid, .unresolvedCoord, .unresolvedFold, .unresolvedPorthole:
            break
        }
    }

    // Designated init for an *unbound* RC: dataSource is left nil, no
    // observers are registered. The intended consumer is `bind(to:)`,
    // typically called from the EventuallyConsistentIntervalTree's
    // doppelganger-binding hook or from fixUpDeserializedIntervalTree:.
    fileprivate init(unboundLocation: Location) {
        self.dataSource = nil
        self.location = unboundLocation
        super.init()
    }

    @objc convenience init(dataSource: ResilientCoordinateDataSource, absCoord: VT100GridAbsCoord) {
        self.init(dataSource: dataSource, location: .coord(absCoord))
    }

    @objc convenience init(dataSource: ResilientCoordinateDataSource, enclosingFold: FoldMark, coord: VT100GridCoord) {
        // No isDoppelganger constraint: mutation-pool RCs hold the
        // progenitor fold mark; main-pool RCs hold the doppelganger.
        // The caller picks the right side for its pool.
        self.init(dataSource: dataSource, location: .fold(mark: .init(enclosingFold), coord: coord))
    }

    /// Construct an unbound RC carrying an abs coord. Status reports
    /// `.unresolved` until `bind(to:)` is called.
    @objc(initUnboundWithAbsCoord:)
    convenience init(unboundAbsCoord: VT100GridAbsCoord) {
        self.init(unboundLocation: .unresolvedCoord(unboundAbsCoord))
    }

    // Decodable's init(from:) must live in the class body for non-final
    // classes (Swift disallows `required` in extensions). The encoding side
    // and the CodingKeys / EncodedKind helpers live in the extension below.
    //
    // Decoded RCs are always unbound — the caller binds them via the
    // tree's hook (for doppelgangers) or fixUpDeserializedIntervalTree:
    // (for progenitors). This removes the need for a dataSource in
    // decoder.userInfo.
    public required convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ResilientCoordinate.CodingKeys.self)
        let kind = try container.decode(ResilientCoordinate.EncodedKind.self, forKey: .kind)
        switch kind {
        case .coord:
            // VT100GridAbsCoord packs x as Int32 and y as Int64. Decode into
            // their respective widths rather than rely on a uniform Int64.
            let x = try container.decode(Int32.self, forKey: .absX)
            let y = try container.decode(Int64.self, forKey: .absY)
            self.init(unboundLocation: .unresolvedCoord(VT100GridAbsCoord(x: x, y: y)))
        case .fold:
            // Decoded as unresolved. A follow-up resolveUnresolved(...) pass
            // upgrades this to `.fold` once the matching FoldMark is in the
            // tree. Until then the RC reports `.unresolved` status.
            let guid = try container.decode(String.self, forKey: .markGuid)
            let x = try container.decode(Int32.self, forKey: .innerX)
            let y = try container.decode(Int32.self, forKey: .innerY)
            self.init(unboundLocation: .unresolvedFold(markGuid: guid,
                                                       coord: VT100GridCoord(x: x, y: y)))
        case .porthole:
            let guid = try container.decode(String.self, forKey: .markGuid)
            let x = try container.decode(Int32.self, forKey: .innerX)
            let y = try container.decode(Int32.self, forKey: .innerY)
            self.init(unboundLocation: .unresolvedPorthole(markGuid: guid,
                                                           coord: VT100GridCoord(x: x, y: y)))
        case .invalid:
            self.init(unboundLocation: .invalid)
        }
    }
}

// Private methods
extension ResilientCoordinate {
    private func observeNotifications(guid: String) {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(linesDidShift(_:)),
                                               name: RCNotificationNames.linesShifted,
                                               object: guid)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(resize(_:)),
                                               name: RCNotificationNames.resize,
                                               object: guid)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didClearFromLineToEnd(_:)),
                                               name: RCNotificationNames.clearToEnd,
                                               object: guid)
    }

    private func invalidateIfCleared(mark: iTermMark?, intervalConverterObj: Any?, absY: Int) {
        if let intervalConverterObj, let mark {
            let markAbsCoord = VT100GridAbsCoordRangeByInvokingIntervalConverter(intervalConverterObj, mark)
            if markAbsCoord.start.y >= absY {
                location = .invalid
            }
        }
    }

    private func status(for coord: VT100GridAbsCoord,
                        in dataSource: ResilientCoordinateDataSource) -> Status {
        let overflow = dataSource.rcScrollbackOverflow
        if overflow > coord.y {
            return .scrolledOff
        }
        let numberOfLines = Int64(dataSource.rcNumberOfLines)
        if coord.y >= numberOfLines + overflow {
            return .truncatedBelow
        }
        if coord.x < 0 || coord.x >= dataSource.rcWidth {
            return .invalid
        }
        return .valid
    }

}

/// A pair of ResilientCoordinates that together describe an interval that
/// adjusts under the same conditions a single ResilientCoordinate does
/// (resize, scrollback overflow, folds, portholes, dataSource dealloc).
///
/// Used by VT100ScreenMark.excludedSubranges to track non-input cell
/// regions (PS2 prefixes, right-prompts) recorded during an OSC 133
/// non-initial A → B pair. Both endpoints share the same dataSource so
/// they receive the same notifications and stay in sync.
///
/// **Inclusivity**: half-open `[start, end)` — `end` is one past the last
/// cell in the range. Matches VT100GridAbsCoordRange's convention.
@objc(iTermResilientCoordinateRange)
class ResilientCoordinateRange: NSObject {
    /// First cell in the range (inclusive).
    @objc let start: ResilientCoordinate
    /// One past the last cell in the range (exclusive).
    @objc let end: ResilientCoordinate

    @objc init(start: ResilientCoordinate, end: ResilientCoordinate) {
        self.start = start
        self.end = end
        super.init()
    }

    @objc convenience init(dataSource: ResilientCoordinateDataSource,
                           absRange: VT100GridAbsCoordRange) {
        let s = ResilientCoordinate(dataSource: dataSource, absCoord: absRange.start)
        let e = ResilientCoordinate(dataSource: dataSource, absCoord: absRange.end)
        self.init(start: s, end: e)
    }

    /// Unbound range; both endpoints are .unresolvedCoord. Use when the
    /// caller doesn't yet have a data source (e.g. a setter on a mark
    /// that hasn't been added to a tree). bestEffortAbsRange still
    /// returns the supplied abs values until the RC is bound.
    @objc(initUnboundWithAbsRange:)
    convenience init(unboundAbsRange: VT100GridAbsCoordRange) {
        let s = ResilientCoordinate(unboundAbsCoord: unboundAbsRange.start)
        let e = ResilientCoordinate(unboundAbsCoord: unboundAbsRange.end)
        self.init(start: s, end: e)
    }

    // Decodable's init(from:) lives in the class body — Swift requires
    // `required` inits to be declared there for non-final classes. encode(to:)
    // and CodingKeys live in the Codable extension at the bottom of the file.
    public required convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: RangeCodingKeys.self)
        let s = try container.decode(ResilientCoordinate.self, forKey: .start)
        let e = try container.decode(ResilientCoordinate.self, forKey: .end)
        self.init(start: s, end: e)
    }

    fileprivate enum RangeCodingKeys: String, CodingKey {
        case start, end
    }

    /// Best-effort projection back to a VT100GridAbsCoordRange. Endpoints
    /// that aren't .valid (e.g. scrolled off, in a fold) contribute
    /// VT100GridAbsCoordInvalid for that axis; callers that need precise
    /// validity should inspect `start.status` / `end.status` directly.
    @objc var absRange: VT100GridAbsCoordRange {
        let s = start.validCoord ?? VT100GridAbsCoordInvalid
        let e = end.validCoord ?? VT100GridAbsCoordInvalid
        return VT100GridAbsCoordRangeMake(s.x, s.y, e.x, e.y)
    }

    /// Best-effort projection that also reports the stored-but-unbound abs
    /// (status `.unresolved` via `.unresolvedCoord`). Used by holders that
    /// must satisfy a setter-then-getter roundtrip before the RC has been
    /// bound to a data source.
    @objc var bestEffortAbsRange: VT100GridAbsCoordRange {
        let s = start.bestEffortAbsCoord
        let e = end.bestEffortAbsCoord
        return VT100GridAbsCoordRangeMake(s.x, s.y, e.x, e.y)
    }
}

// Public API
extension ResilientCoordinate {
    @objc
    var status: Status {
        switch location {
        case .invalid:
            return .invalid
        case .unresolvedCoord, .unresolvedFold, .unresolvedPorthole:
            // Either pre-bind (dataSource is nil) or post-bind but pre
            // mark-resolution — either way, not yet usable.
            return .unresolved
        case let .coord(coord):
            // The weak dataSource ref auto-zeros when its session deallocs;
            // that's our "session gone" signal — no notification needed.
            guard let dataSource else { return .invalid }
            return status(for: coord, in: dataSource)
        case let .fold(mark: mark, coord: _):
            guard dataSource != nil else { return .invalid }
            guard mark.value != nil else { return .invalid }
            return .inFold
        case let .porthole(mark: mark, coord: _):
            guard dataSource != nil else { return .invalid }
            guard mark.value != nil else { return .invalid }
            return .inPorthole
        }
    }

    @objc var coord: VT100GridAbsCoord {
        guard status == .valid else {
            return VT100GridAbsCoordInvalid
        }
        switch location {
        case let .coord(coord):
            return coord
        case .fold, .porthole, .unresolvedCoord, .unresolvedFold, .unresolvedPorthole, .invalid:
            it_fatalError("Can't get coord \(d(location))")
        }
    }

    var validCoord: VT100GridAbsCoord? {
        return status == .valid ? coord : nil
    }

    /// Returns the underlying abs coord for `.coord` AND `.unresolvedCoord`
    /// locations (the latter is the "set but not bound yet" case), and
    /// VT100GridAbsCoordInvalid for everything else. Distinct from
    /// `validCoord`, which excludes the unbound case. Use this when a
    /// caller needs to satisfy a setter-then-immediate-getter roundtrip
    /// before the RC has been bound to a data source.
    @objc var bestEffortAbsCoord: VT100GridAbsCoord {
        switch location {
        case .coord(let c), .unresolvedCoord(let c):
            return c
        case .fold, .porthole, .unresolvedFold, .unresolvedPorthole, .invalid:
            return VT100GridAbsCoordInvalid
        }
    }

    var coordWithinFold: VT100GridCoord? {
        switch location {
        case .coord, .unresolvedCoord, .porthole, .unresolvedPorthole, .invalid:
            return nil
        case .fold(mark: _, coord: let coord):
            return coord
        case .unresolvedFold(markGuid: _, coord: let coord):
            // The within-fold coord is known even when the FoldMark hasn't
            // been bound yet. Consumers that need the mark itself should
            // check `foldInfo`, which returns nil until resolution.
            return coord
        }
    }

    struct FoldInfo {
        var mark: FoldMark
        var coord: VT100GridCoord
    }
    var foldInfo: FoldInfo? {
        switch location {
        case let .fold(mark: mark, coord: coord):
            if let value = mark.value {
                return FoldInfo(mark: value, coord: coord)
            } else {
                return nil
            }
        default:
            return nil
        }
    }

    /// ObjC-accessible wrapper for foldInfo.
    @objc(iTermResilientCoordinateFoldInfo)
    class ObjCFoldInfo: NSObject {
        @objc let mark: FoldMark
        @objc let coord: VT100GridCoord
        init(mark: FoldMark, coord: VT100GridCoord) {
            self.mark = mark
            self.coord = coord
        }
    }

    @objc var objcFoldInfo: ObjCFoldInfo? {
        guard let info = foldInfo else { return nil }
        return ObjCFoldInfo(mark: info.mark, coord: info.coord)
    }

    var portholeInfo: (PortholeMark, VT100GridCoord)? {
        switch location {
        case let .porthole(mark: mark, coord: coord):
            if let value = mark.value {
                return (value, coord)
            } else {
                return nil
            }
        default:
            return nil
        }
    }
}

// Notification handlers
extension ResilientCoordinate {
    @objc
    private func didClearFromLineToEnd(_ notification: NSNotification) {
        guard let absY = notification.userInfo?[RCClearToEndNotification.absYKey] as? Int else {
            it_fatalError("No absY in user info \(d(notification.userInfo))")
        }
        let intervalConverterObj = notification.userInfo?[RCClearToEndNotification.intervalConverterKey]
        switch location {
        case .coord(let coord):
            if coord.y >= absY {
                location = .invalid
            }
        case .fold(mark: let mark, coord: _):
            invalidateIfCleared(mark: mark.value, intervalConverterObj: intervalConverterObj, absY: absY)
        case .porthole(mark: let mark, coord: _):
            invalidateIfCleared(mark: mark.value, intervalConverterObj: intervalConverterObj, absY: absY)
        case .unresolvedCoord, .unresolvedFold, .unresolvedPorthole:
            // Unresolved RCs are pre-resolution: until bind/resolveUnresolved
            // runs, the notification handlers leave them alone. (For .unresolved*
            // we also don't register observers in the first place — but defend
            // here in case a notification dispatches before deinit cleans up.)
            break
        case .invalid:
            break
        }
    }

    @objc
    private func resize(_ notification: NSNotification) {
        guard let guid = notification.object as? String else {
            DLog("Invalid notification object \(d(notification.object))")
            return
        }
        guard guid == dataSource?.rcGuid else {
            return
        }
        guard let unsafeCoord else {
            return
        }
        guard let convertObj = notification.userInfo?[RCResizeNotification.convertKey] else {
            return
        }
        let converted = VT100GridAbsCoordByInvokingConverter(convertObj, unsafeCoord)
        if VT100GridAbsCoordIsValid(converted) {
            location = .coord(converted)
        } else {
            location = .invalid
        }
    }

    // Does not check if the coord has been truncated or lost to scrollback overflow.
    // Returns nil if it's in a fold, porthole, unresolved, or dead data source.
    private var unsafeCoord: VT100GridAbsCoord? {
        guard dataSource != nil else {
            return nil
        }
        switch location {
        case .coord(let coord):
            return coord
        case .fold, .porthole, .unresolvedCoord, .unresolvedFold, .unresolvedPorthole, .invalid:
            return nil
        }
    }

    @objc
    private func linesDidShift(_ notification: NSNotification) {
        guard let guid = notification.object as? String else {
            DLog("Invalid notification object \(d(notification.object))")
            return
        }
        guard guid == dataSource?.rcGuid else {
            return
        }
        // genericMark is OPTIONAL: the mutation-thread linesShifted post
        // for the .fold path runs inside replaceRange:withLines: before
        // the caller has created its FoldMark, so the post has no mark in
        // userInfo. The shift-up sub-case below doesn't need a mark; only
        // the entering-fold / matching-unfold sub-cases do, and they
        // explicitly check for nil before using it.
        guard let reasonRaw = (notification.userInfo?[LinesShiftedNotification.reasonKey] as? NSNumber)?.intValue,
              let reason = iTermLinesShiftedReason(rawValue: reasonRaw),
              let absLine = (notification.userInfo?[LinesShiftedNotification.absLineKey] as? NSNumber)?.int64Value,
              let delta = (notification.userInfo?[LinesShiftedNotification.deltaKey] as? NSNumber)?.int32Value else {
            DLog("Bad user info \(d(notification.userInfo))")
            return
        }
        let genericMark = notification.userInfo?[LinesShiftedNotification.markKey] as? iTermMark
        let converterObj = notification.userInfo?[LinesShiftedNotification.converterKey]
        switch reason {
        case .fold:
            it_assert(delta < 0)
            let removedRange = absLine...(absLine - Int64(delta))
            if let coord = unsafeCoord {
                if removedRange.contains(coord.y),
                   let foldMark = genericMark as? FoldMark {
                    // We are entering a fold
                    location = .fold(mark: .init(foldMark),
                                     coord: VT100GridCoord(x: coord.x,
                                                           y: Int32(clamping: coord.y - absLine)))
                    return
                }
                if absLine < coord.y {
                    // Folded above us, shift our coord up.
                    location = .coord(VT100GridAbsCoord(x: coord.x, y: coord.y + Int64(delta)))
                }
            }
        case .unfold:
            it_assert(delta > 0)
            if let foldInfo, genericMark === foldInfo.mark {
                // Unfolding our enclosing fold. The stored coord is relative to the
                // start of the original folded range, so restore it directly.
                let converted: VT100GridCoord
                if let converterObj {
                    let value = VT100GridCoordByInvokingConverter(converterObj, foldInfo.coord)
                    converted = VT100GridCoordIsValid(value) ? value : foldInfo.coord
                } else {
                    converted = foldInfo.coord
                }
                location = .coord(VT100GridAbsCoord(x: 0, y: absLine) + converted)
                return
            }
            if let coord = unsafeCoord, absLine < coord.y {
                // Unfolding above us.
                location = .coord(coord + VT100GridSize(width: 0, height: delta))
                return
            }
        case .portholeAdded:
            if let replacedNSRange = (notification.userInfo?[LinesShiftedNotification.replacedRangeKey] as? NSValue)?.rangeValue,
               let replacedRange = Range(replacedNSRange),
               let portholeMark = genericMark as? PortholeMark {
                if let coord = unsafeCoord {
                    if replacedRange.contains(Int(coord.y)) {
                        // We have entered a porthole
                        location = .porthole(mark: .init(portholeMark),
                                             coord: VT100GridCoord(x: coord.x,
                                                                   y: Int32(clamping: coord.y - absLine)))
                        return
                    }
                    if absLine < coord.y {
                        // A porthole was added above us
                        location = .coord(coord + VT100GridSize(width: 0, height: delta))
                        return
                    }
                }
                // TODO: Deal with folds entering portholes and portholes entering portholes (is that even possible?)
            }
        case .portholeRemoved:
            if let portholeMark = genericMark as? PortholeMark {
                if let coord = unsafeCoord {
                    if absLine < coord.y {
                        // A porthole was removed above us
                        location = .coord(coord + VT100GridSize(width: 0, height: delta))
                        return
                    }
                } else if let portholeInfo, portholeMark === portholeInfo.0 {
                    // Our porthole was removed
                    guard let converterObj else {
                        DLog("Missing or invalid converter \(d(notification.userInfo))")
                        return
                    }
                    let converted = VT100GridCoordByInvokingConverter(converterObj, portholeInfo.1)
                    location = .coord(VT100GridAbsCoord(x: 0, y: absLine) + converted)
                }
            }
        case .portholeResized:
            if genericMark is PortholeMark, let coord = unsafeCoord, absLine < coord.y {
                // A porthole was resized above us
                location = .coord(coord + VT100GridSize(width: 0, height: delta))
                return
            }
        @unknown default:
            it_fatalError()
        }
    }
}

// MARK: - Resolution

extension ResilientCoordinate {
    /// Binds an unbound RC to `dataSource` and registers notification
    /// observers. Idempotent — no-op when `self.dataSource` is already set.
    ///
    /// Transitions `.unresolvedCoord(c)` to `.coord(c)`. Leaves
    /// `.unresolvedFold` / `.unresolvedPorthole` as-is (they need their
    /// target mark via `resolveUnresolved(foldMarkLookup:...)`). Doesn't
    /// touch `.coord` / `.fold` / `.porthole` / `.invalid` locations
    /// other than possibly attaching observers if they were missing.
    @objc(bindToDataSource:)
    func bind(to dataSource: ResilientCoordinateDataSource) {
        if self.dataSource != nil {
            return
        }
        self.dataSource = dataSource
        switch location {
        case let .unresolvedCoord(c):
            location = .coord(c)
        case .coord, .fold, .porthole, .unresolvedFold, .unresolvedPorthole, .invalid:
            break
        }
        // Skip observer registration for `.invalid` (terminal) and the
        // unresolved fold/porthole cases (they have nothing to observe
        // until resolution upgrades them). `.unresolvedCoord` transitioned
        // above, so its case lands in `.coord` here — register.
        switch location {
        case .coord, .fold, .porthole:
            observeNotifications(guid: dataSource.rcGuid)
        case .invalid, .unresolvedCoord, .unresolvedFold, .unresolvedPorthole:
            break
        }
    }

    /// Detach from the current dataSource (if any) and re-attach to
    /// `dataSource`. Preserves the underlying location (a `.coord`
    /// stays a `.coord` with the same abs y; `.fold` / `.porthole`
    /// keep their target marks). Used by tree migration so the mark
    /// observes notifications on the destination tree's guid.
    @objc(rebindToDataSource:)
    func rebind(to dataSource: ResilientCoordinateDataSource) {
        if self.dataSource === dataSource {
            return
        }
        if self.dataSource != nil {
            NotificationCenter.default.removeObserver(self)
            self.dataSource = nil
        }
        bind(to: dataSource)
    }

    /// Upgrades an `.unresolvedFold` / `.unresolvedPorthole` to its bound
    /// `.fold` / `.porthole` equivalent by looking the target mark up by
    /// guid. Returns `true` if the coord was unresolved and got resolved,
    /// `false` if it was already resolved or the lookup couldn't find the
    /// mark. Intended to run in a second pass after a whole interval tree
    /// has been decoded (so all FoldMark / PortholeMark targets exist).
    @discardableResult
    func resolveUnresolved(foldMarkLookup: (String) -> FoldMark?,
                           portholeMarkLookup: (String) -> PortholeMark?) -> Bool {
        switch location {
        case let .unresolvedFold(markGuid: guid, coord: coord):
            guard let foldMark = foldMarkLookup(guid) else { return false }
            // No isDoppelganger constraint — see init(enclosingFold:).
            location = .fold(mark: .init(foldMark), coord: coord)
            // Now that we have a resolved fold and (likely) a bound
            // dataSource, register observers so future notifications hit.
            if let ds = dataSource {
                observeNotifications(guid: ds.rcGuid)
            }
            return true
        case let .unresolvedPorthole(markGuid: guid, coord: coord):
            guard let portholeMark = portholeMarkLookup(guid) else { return false }
            location = .porthole(mark: .init(portholeMark), coord: coord)
            if let ds = dataSource {
                observeNotifications(guid: ds.rcGuid)
            }
            return true
        default:
            return false
        }
    }

    /// ObjC-friendly bridge: lookup blocks return the bound mark, or nil
    /// when the guid isn't known. Use the Swift overload above from Swift
    /// callers — it's the same logic without the @convention(block) noise.
    @objc(resolveUnresolvedWithFoldMarkLookup:portholeMarkLookup:)
    @discardableResult
    func resolveUnresolvedObjC(
        foldMarkLookup: @convention(block) (String) -> FoldMark?,
        portholeMarkLookup: @convention(block) (String) -> PortholeMark?
    ) -> Bool {
        return resolveUnresolved(foldMarkLookup: foldMarkLookup,
                                 portholeMarkLookup: portholeMarkLookup)
    }
}

extension ResilientCoordinateRange {
    /// Bind both endpoints to `dataSource`. Idempotent; safe to call on
    /// already-bound endpoints.
    @objc(bindToDataSource:)
    func bind(to dataSource: ResilientCoordinateDataSource) {
        start.bind(to: dataSource)
        end.bind(to: dataSource)
    }

    /// Detach both endpoints (if bound) and re-bind to `dataSource`.
    @objc(rebindToDataSource:)
    func rebind(to dataSource: ResilientCoordinateDataSource) {
        start.rebind(to: dataSource)
        end.rebind(to: dataSource)
    }

    /// Convenience: resolve both endpoints. Returns true if either endpoint
    /// transitioned from unresolved to resolved.
    @discardableResult
    func resolveUnresolved(foldMarkLookup: (String) -> FoldMark?,
                           portholeMarkLookup: (String) -> PortholeMark?) -> Bool {
        let s = start.resolveUnresolved(foldMarkLookup: foldMarkLookup,
                                        portholeMarkLookup: portholeMarkLookup)
        let e = end.resolveUnresolved(foldMarkLookup: foldMarkLookup,
                                      portholeMarkLookup: portholeMarkLookup)
        return s || e
    }

    @objc(resolveUnresolvedWithFoldMarkLookup:portholeMarkLookup:)
    @discardableResult
    func resolveUnresolvedObjC(
        foldMarkLookup: @convention(block) (String) -> FoldMark?,
        portholeMarkLookup: @convention(block) (String) -> PortholeMark?
    ) -> Bool {
        return resolveUnresolved(foldMarkLookup: foldMarkLookup,
                                 portholeMarkLookup: portholeMarkLookup)
    }
}

// MARK: - Codable

extension ResilientCoordinate {
    fileprivate enum CodingKeys: String, CodingKey {
        case kind
        case absX, absY        // .coord / .unresolvedCoord
        case innerX, innerY    // .fold / .porthole (cell relative to the region)
        case markGuid          // .fold / .porthole (guid of FoldMark / PortholeMark)
    }

    fileprivate enum EncodedKind: String, Codable {
        case coord, fold, porthole, invalid
    }
}

extension ResilientCoordinate: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch location {
        case .coord(let c), .unresolvedCoord(let c):
            // .coord and .unresolvedCoord share the wire format — the
            // unbound/bound distinction is reconstructed at decode time
            // (decode always produces unbound; a later bind step lifts it).
            try container.encode(EncodedKind.coord, forKey: .kind)
            try container.encode(c.x, forKey: .absX)
            try container.encode(c.y, forKey: .absY)
        case .fold(let mark, let inner):
            // If the FoldMark died, the coord is no longer rejoinable on a
            // future decode. Encode as `.invalid` rather than emit a guid
            // that won't resolve.
            guard let foldMark = mark.value else {
                try container.encode(EncodedKind.invalid, forKey: .kind)
                return
            }
            try container.encode(EncodedKind.fold, forKey: .kind)
            try container.encode(foldMark.guid, forKey: .markGuid)
            try container.encode(inner.x, forKey: .innerX)
            try container.encode(inner.y, forKey: .innerY)
        case .unresolvedFold(let guid, let inner):
            // We never bound this to a live mark — round-trip through the
            // same guid so the next decoder can try again.
            try container.encode(EncodedKind.fold, forKey: .kind)
            try container.encode(guid, forKey: .markGuid)
            try container.encode(inner.x, forKey: .innerX)
            try container.encode(inner.y, forKey: .innerY)
        case .porthole(let mark, let inner):
            guard let portholeMark = mark.value else {
                try container.encode(EncodedKind.invalid, forKey: .kind)
                return
            }
            try container.encode(EncodedKind.porthole, forKey: .kind)
            try container.encode(portholeMark.guid, forKey: .markGuid)
            try container.encode(inner.x, forKey: .innerX)
            try container.encode(inner.y, forKey: .innerY)
        case .unresolvedPorthole(let guid, let inner):
            try container.encode(EncodedKind.porthole, forKey: .kind)
            try container.encode(guid, forKey: .markGuid)
            try container.encode(inner.x, forKey: .innerX)
            try container.encode(inner.y, forKey: .innerY)
        case .invalid:
            try container.encode(EncodedKind.invalid, forKey: .kind)
        }
    }

    // init(from:) lives in the class body — Swift requires `required` inits
    // to be declared there for non-final classes.
}

extension ResilientCoordinateRange: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: RangeCodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
    }

    // init(from:) is declared in the class body — see comment there.
}

// MARK: - Unbound copy (for doppelganger creation)

extension ResilientCoordinate {
    /// Returns a structurally-equivalent unbound RC suitable for the
    /// doppelganger side. Transformations:
    /// - `.coord` → `.unresolvedCoord` so the doppelganger's bind(to:)
    ///   knows to attach observers against the main-thread pool.
    /// - `.fold(progenitor, …)` → `.fold(progenitor.doppelganger, …)`.
    ///   Mutation-pool RCs hold the progenitor fold mark; the
    ///   doppelganger holder must hold the doppelganger fold mark so
    ///   main-thread reads of the fold mark (e.g. `entry.interval`
    ///   inside the clearToEnd converter) don't race the mutation
    ///   thread's writes to the progenitor's `entry`.
    /// - `.porthole(progenitor, …)` → same flip.
    /// - `.unresolved*` / `.invalid` → preserved as-is. For
    ///   `.unresolvedFold` / `.unresolvedPorthole`, the doppelganger
    ///   resolution pass (in fixUpDeserializedIntervalTree:) will
    ///   resolve them to doppelganger fold/porthole marks via a
    ///   doppelganger lookup.
    /// - `.fold` / `.porthole` whose WeakBox is already dead become
    ///   `.invalid` since we can't get a doppelganger for a dead mark.
    /// - If the source mark is *already* a doppelganger (shouldn't
    ///   happen since unboundCopy runs from -copyWithZone on the
    ///   progenitor holder, but defensive), keep it — calling
    ///   .doppelganger on a doppelganger asserts in iTermMark.
    @objc
    func unboundCopy() -> ResilientCoordinate {
        let newLocation: Location
        switch location {
        case .coord(let c):
            newLocation = .unresolvedCoord(c)
        case let .fold(mark: mark, coord: coord):
            if let m = mark.value {
                let target: FoldMark = m.isDoppelganger ? m : (m.doppelganger() as! FoldMark)
                newLocation = .fold(mark: .init(target), coord: coord)
            } else {
                newLocation = .invalid
            }
        case let .porthole(mark: mark, coord: coord):
            if let m = mark.value {
                let target: PortholeMark = m.isDoppelganger ? m : (m.doppelganger() as! PortholeMark)
                newLocation = .porthole(mark: .init(target), coord: coord)
            } else {
                newLocation = .invalid
            }
        case .unresolvedCoord, .unresolvedFold, .unresolvedPorthole, .invalid:
            newLocation = location
        }
        return ResilientCoordinate(unboundLocation: newLocation)
    }
}

extension ResilientCoordinateRange {
    @objc
    func unboundCopy() -> ResilientCoordinateRange {
        return ResilientCoordinateRange(start: start.unboundCopy(),
                                        end: end.unboundCopy())
    }
}

// MARK: - NSDictionary bridge for ObjC serialization

extension ResilientCoordinate {
    /// ObjC-friendly bridge: produces an NSDictionary suitable for embedding
    /// inside the legacy plist-shaped mark dictionaries that
    /// VT100ScreenMark.dictionaryValue emits. The shape matches what
    /// Codable's `encode(to:)` would write, so a future Codable-based
    /// consumer can still decode it; we just skip the
    /// struct -> JSON bytes -> NSDictionary detour.
    @objc var dictionaryValue: NSDictionary {
        let dict = NSMutableDictionary()
        switch location {
        case .coord(let c), .unresolvedCoord(let c):
            dict[CodingKeys.kind.rawValue] = EncodedKind.coord.rawValue
            dict[CodingKeys.absX.rawValue] = NSNumber(value: c.x)
            dict[CodingKeys.absY.rawValue] = NSNumber(value: c.y)
        case .fold(let mark, let inner):
            // If the FoldMark died, the coord is no longer rejoinable on a
            // future decode. Encode as `.invalid` rather than emit a guid
            // that won't resolve.
            guard let foldMark = mark.value else {
                dict[CodingKeys.kind.rawValue] = EncodedKind.invalid.rawValue
                return dict
            }
            dict[CodingKeys.kind.rawValue] = EncodedKind.fold.rawValue
            dict[CodingKeys.markGuid.rawValue] = foldMark.guid
            dict[CodingKeys.innerX.rawValue] = NSNumber(value: inner.x)
            dict[CodingKeys.innerY.rawValue] = NSNumber(value: inner.y)
        case .unresolvedFold(let guid, let inner):
            dict[CodingKeys.kind.rawValue] = EncodedKind.fold.rawValue
            dict[CodingKeys.markGuid.rawValue] = guid
            dict[CodingKeys.innerX.rawValue] = NSNumber(value: inner.x)
            dict[CodingKeys.innerY.rawValue] = NSNumber(value: inner.y)
        case .porthole(let mark, let inner):
            guard let portholeMark = mark.value else {
                dict[CodingKeys.kind.rawValue] = EncodedKind.invalid.rawValue
                return dict
            }
            dict[CodingKeys.kind.rawValue] = EncodedKind.porthole.rawValue
            dict[CodingKeys.markGuid.rawValue] = portholeMark.guid
            dict[CodingKeys.innerX.rawValue] = NSNumber(value: inner.x)
            dict[CodingKeys.innerY.rawValue] = NSNumber(value: inner.y)
        case .unresolvedPorthole(let guid, let inner):
            dict[CodingKeys.kind.rawValue] = EncodedKind.porthole.rawValue
            dict[CodingKeys.markGuid.rawValue] = guid
            dict[CodingKeys.innerX.rawValue] = NSNumber(value: inner.x)
            dict[CodingKeys.innerY.rawValue] = NSNumber(value: inner.y)
        case .invalid:
            dict[CodingKeys.kind.rawValue] = EncodedKind.invalid.rawValue
        }
        return dict
    }

    /// Decode a previously-serialized RC. The returned RC is unbound
    /// (status `.unresolved` or `.invalid`) - call `bind(to:)` before
    /// using it, or rely on the EventuallyConsistentIntervalTree hook /
    /// fixUpDeserializedIntervalTree: to do the binding. Accepts the
    /// shape produced by either `dictionaryValue` or Codable.
    @objc(coordinateFromDictionary:)
    static func from(dictionary: NSDictionary) -> ResilientCoordinate? {
        guard let kindRaw = dictionary[CodingKeys.kind.rawValue] as? String,
              let kind = EncodedKind(rawValue: kindRaw) else {
            RLog("ResilientCoordinate.from(dictionary:): missing/invalid kind")
            return nil
        }
        let location: Location
        switch kind {
        case .coord:
            guard let x = (dictionary[CodingKeys.absX.rawValue] as? NSNumber)?.int32Value,
                  let y = (dictionary[CodingKeys.absY.rawValue] as? NSNumber)?.int64Value else {
                DLog("ResilientCoordinate.from(dictionary:): missing absX/absY for .coord")
                return nil
            }
            location = .unresolvedCoord(VT100GridAbsCoord(x: x, y: y))
        case .fold:
            guard let guid = dictionary[CodingKeys.markGuid.rawValue] as? String,
                  let x = (dictionary[CodingKeys.innerX.rawValue] as? NSNumber)?.int32Value,
                  let y = (dictionary[CodingKeys.innerY.rawValue] as? NSNumber)?.int32Value else {
                DLog("ResilientCoordinate.from(dictionary:): missing markGuid/innerX/innerY for .fold")
                return nil
            }
            location = .unresolvedFold(markGuid: guid, coord: VT100GridCoord(x: x, y: y))
        case .porthole:
            guard let guid = dictionary[CodingKeys.markGuid.rawValue] as? String,
                  let x = (dictionary[CodingKeys.innerX.rawValue] as? NSNumber)?.int32Value,
                  let y = (dictionary[CodingKeys.innerY.rawValue] as? NSNumber)?.int32Value else {
                DLog("ResilientCoordinate.from(dictionary:): missing markGuid/innerX/innerY for .porthole")
                return nil
            }
            location = .unresolvedPorthole(markGuid: guid, coord: VT100GridCoord(x: x, y: y))
        case .invalid:
            location = .invalid
        }
        return ResilientCoordinate(unboundLocation: location)
    }
}

extension ResilientCoordinateRange {
    /// Direct NSDictionary projection, matching the Codable wire shape:
    /// `{ "start": <RC dict>, "end": <RC dict> }`.
    @objc var dictionaryValue: NSDictionary {
        return [
            RangeCodingKeys.start.rawValue: start.dictionaryValue,
            RangeCodingKeys.end.rawValue: end.dictionaryValue,
        ]
    }

    /// Decode an RCRange. Both endpoints come back unbound; call
    /// `bind(to:)` before consuming. Accepts the shape produced by either
    /// `dictionaryValue` or Codable.
    @objc(rangeFromDictionary:)
    static func from(dictionary: NSDictionary) -> ResilientCoordinateRange? {
        guard let startDict = dictionary[RangeCodingKeys.start.rawValue] as? NSDictionary,
              let endDict = dictionary[RangeCodingKeys.end.rawValue] as? NSDictionary,
              let startRC = ResilientCoordinate.from(dictionary: startDict),
              let endRC = ResilientCoordinate.from(dictionary: endDict) else {
            RLog("ResilientCoordinateRange.from(dictionary:): missing/invalid start or end")
            return nil
        }
        return ResilientCoordinateRange(start: startRC, end: endRC)
    }
}
