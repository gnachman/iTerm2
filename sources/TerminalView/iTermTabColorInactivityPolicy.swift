//
//  iTermTabColorInactivityPolicy.swift
//  iTerm2SharedARC
//

import Foundation

/// Decides whether a configured tab color is still active after a period of
/// terminal inactivity. The clock stays outside this policy so callers and
/// tests can exercise long timeouts without timers or sleeps.
@objc(iTermTabColorInactivityPolicy)
public final class iTermTabColorInactivityPolicy: NSObject {
    @objc(shouldShowCustomColorWithExpirationHours:inactiveSeconds:)
    public static func shouldShowCustomColor(expirationHours: Double,
                                             inactiveSeconds: TimeInterval) -> Bool {
        guard expirationHours > 0 else {
            return true
        }
        return inactiveSeconds < expirationHours * 60 * 60
    }
}
