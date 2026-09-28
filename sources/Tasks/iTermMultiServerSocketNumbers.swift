//
//  iTermMultiServerSocketNumbers.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/23/26.
//

import Foundation

/// Picks the socket number to use when this process wants to launch a *new* iTermServer.
///
/// Socket numbers must not collide with connections already in the registry. Those are
/// servers inherited from an earlier iTerm2 instance (adopted orphans), and reusing their
/// number would hand back the existing connection instead of launching a fresh server.
/// See `iTermMultiServerConnection`.
@objc(iTermMultiServerSocketNumbers)
class MultiServerSocketNumbers: NSObject {
    /// Lowest socket number greater than or equal to `start` that is not in `inUse`.
    /// Socket numbers are 1-based, so a `start` below 1 is treated as 1.
    @objc(firstUnusedNumberFrom:inUse:)
    static func firstUnusedNumber(from start: Int, inUse: [NSNumber]) -> Int {
        let used = Set(inUse.map { $0.intValue })
        var candidate = max(start, 1)
        while used.contains(candidate) {
            candidate += 1
        }
        return candidate
    }
}
