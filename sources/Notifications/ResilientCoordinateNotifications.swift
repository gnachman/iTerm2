//
//  ResilientCoordinateNotifications.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/28/26.
//

import Foundation

// MARK: - Notification Names

// These notifications are posted with the data source's rcGuid as the object,
// allowing ResilientCoordinate instances to filter by guid.

@objc(iTermRCNotificationNames)
class RCNotificationNames: NSObject {
    /// Lines were shifted (fold/unfold/porthole add/remove/resize).
    /// This reuses the existing LinesShiftedNotification.name.
    @objc static let linesShifted = LinesShiftedNotification.name

    /// A resize occurred and resilient coordinates should be converted.
    @objc static let resize = NSNotification.Name("iTermRCResize")

    /// Screen was cleared from an absolute line to the end.
    @objc static let clearToEnd = NSNotification.Name("iTermRCClearToEnd")

    /// The data source is being deallocated.
    @objc static let dataSourceDealloc = NSNotification.Name("iTermRCDataSourceDealloc")
}

// MARK: - Posting Helpers

/// Helpers for posting resize notifications to ResilientCoordinate.
@objc(iTermRCResizeNotification)
class RCResizeNotification: NSObject {
    @objc static let convertKey = "convert"

    /// Posts a resize notification.
    /// - Parameters:
    ///   - guid: The data source's rcGuid.
    ///   - converter: A block `(VT100GridAbsCoord) -> VT100GridAbsCoord`, passed as `id`.
    ///                Returns VT100GridAbsCoordInvalid if the coord can't be converted.
    ///                The block must already be heap-allocated (copied) before calling.
    @objc static func post(guid: String, converter: Any) {
        NotificationCenter.default.post(
            name: RCNotificationNames.resize,
            object: guid,
            userInfo: [convertKey: converter])
    }
}

/// Helpers for posting clear-to-end notifications to ResilientCoordinate.
@objc(iTermRCClearToEndNotification)
class RCClearToEndNotification: NSObject {
    @objc static let absYKey = "absY"
    @objc static let intervalConverterKey = "intervalConverter"

    /// Posts a clear-to-end notification.
    /// - Parameters:
    ///   - guid: The data source's rcGuid.
    ///   - absY: The absolute line from which the clear starts.
    ///   - intervalConverter: A block that converts an IntervalTreeImmutableObject to its
    ///                        VT100GridAbsCoordRange, passed as `id`. May be nil.
    @objc static func post(guid: String,
                           absY: Int64,
                           intervalConverter: Any?) {
        var userInfo: [String: Any] = [absYKey: NSNumber(value: absY)]
        if let intervalConverter {
            userInfo[intervalConverterKey] = intervalConverter
        }
        NotificationCenter.default.post(
            name: RCNotificationNames.clearToEnd,
            object: guid,
            userInfo: userInfo)
    }
}

/// Helpers for posting data-source-dealloc notifications to ResilientCoordinate.
@objc(iTermRCDataSourceDeallocNotification)
class RCDataSourceDeallocNotification: NSObject {
    @objc static func post(guid: String) {
        NotificationCenter.default.post(
            name: RCNotificationNames.dataSourceDealloc,
            object: guid)
    }
}
