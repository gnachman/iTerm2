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

// A coordinate that correctly describes a location and is resilient to folding, scrolling,
// and so on.
@objc(iTermResilientCoordinate)
class ResilientCoordinate: NSObject {
    private weak let dataSource: ResilientCoordinateDataSource?
    private enum Location {
        case coord(VT100GridAbsCoord)
        case fold(mark: WeakBox<FoldMark>, coord: VT100GridCoord)
        case porthole(mark: WeakBox<PortholeMark>, coord: VT100GridCoord)
        case invalid
    }
    private var location: Location {
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
        case retired // Session no longer exists
        case invalid  // bogus x coordinate, shouldn't really happen.
        case inPorthole  // Coordinate belongs to a region that was replaced with a porthole
    }

    @objc init(dataSource: ResilientCoordinateDataSource, absCoord: VT100GridAbsCoord) {
        self.dataSource = dataSource
        self.location = .coord(absCoord)

        super.init()

        observeNotifications(guid: dataSource.rcGuid)
    }

    @objc init(dataSource: ResilientCoordinateDataSource, enclosingFold: FoldMark, coord: VT100GridCoord) {
        it_assert(enclosingFold.isDoppelganger)

        self.dataSource = dataSource
        self.location = .fold(mark: .init(enclosingFold), coord: coord)

        super.init()

        observeNotifications(guid: dataSource.rcGuid)
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
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(dataSourceDidDealloc(_:)),
                                               name: RCNotificationNames.dataSourceDealloc,
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

// Public API
extension ResilientCoordinate {
    @objc
    var status: Status {
        guard let dataSource else {
            return .retired
        }
        switch location {
        case let .coord(coord):
            return status(for: coord, in: dataSource)
        case let .fold(mark: mark, coord: _):
            guard mark.value != nil else {
                return .retired
            }
            return .inFold
        case let .porthole(mark: mark, coord: _):
            guard mark.value != nil else {
                return .retired
            }
            return .inPorthole
        case .invalid:
            return .invalid
        }
    }

    @objc var coord: VT100GridAbsCoord {
        guard status == .valid else {
            return VT100GridAbsCoordInvalid
        }
        switch location {
        case let .coord(coord):
            return coord
        case .fold, .porthole, .invalid:
            it_fatalError("Can't get coord \(d(location))")
        }
    }

    var validCoord: VT100GridAbsCoord? {
        return status == .valid ? coord : nil
    }

    var coordWithinFold: VT100GridCoord? {
        switch location {
        case .coord, .porthole, .invalid:
            return nil
        case .fold(mark: _, coord: let coord):
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
    private func dataSourceDidDealloc(_ notification: NSNotification) {
        location = .invalid
    }

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
    // Returns nil if it's in a fold, porthole, or dead data source.
    private var unsafeCoord: VT100GridAbsCoord? {
        guard dataSource != nil else {
            return nil
        }
        switch location {
        case .coord(let coord):
            return coord
        case .fold, .porthole, .invalid:
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
        guard let reasonRaw = (notification.userInfo?[LinesShiftedNotification.reasonKey] as? NSNumber)?.intValue,
              let reason = iTermLinesShiftedReason(rawValue: reasonRaw),
              let genericMark = notification.userInfo?[LinesShiftedNotification.markKey] as? iTermMark,
              let absLine = (notification.userInfo?[LinesShiftedNotification.absLineKey] as? NSNumber)?.int64Value,
              let delta = (notification.userInfo?[LinesShiftedNotification.deltaKey] as? NSNumber)?.int32Value else {
            DLog("Bad user info \(d(notification.userInfo))")
            return
        }
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
