//
//  DeadlineMonitor.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/26/23.
//

import Foundation

/// Lets you ask if some amount of time has passed.
@objc(iTermDeadlineMonitor)
class DeadlineMonitor: NSObject {
    private let end: TimeInterval

    private static var now: TimeInterval {
        NSDate.it_timeInterval(forAbsoluteTime: mach_absolute_time())
    }

    @objc
    init(duration: TimeInterval) {
        end = Self.now + duration
    }

    /// Returns: whether the deadline remains unreached.
    @objc var pending: Bool {
        return Self.now < end
    }
}
