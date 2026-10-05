//
//  ShardMapRaceArbiter.swift
//  CompanionCore
//
//  Picks the winner when ShardMapLoader fetches the map from the primary
//  resolver and its mirrors at once. Pure: it takes each event as it happens
//  and says whether to keep waiting, so the rules can be tested with exact
//  event orders. The rules:
//
//  - The primary is authoritative: with a map loaded, its map wins as soon as
//    it arrives, even if not newer (that just means nothing changed). The one
//    exception is a mirror map already in hand that the loader would adopt:
//    then the primary's answer came from a lagging edge, and the newer map
//    wins. On a cold start, a primary map below the persisted floor (also a
//    lagging edge) would be discarded by refresh(), so it is treated like an
//    outdated mirror copy and the mirrors get their chance.
//  - A mirror may lag (GitHub Pages caches for ten minutes), so its map only
//    competes if it is usable: the loader would adopt it, or it is the very
//    version already loaded (which confirms the loaded map is still current,
//    as the primary's would). A usable mirror map is held until the delay
//    elapses or the primary fails, then wins.
//  - An older mirror map never wins. It counts as a failed attempt (an
//    outdated copy; see rejection(of:from:)), so if no source produces a
//    usable map the race fails, rather than handing back a map that would be
//    ignored.
//  - If every source fails, the race fails. What each failure was is not the
//    arbiter's concern: ShardMapFetchProgress keeps that record.
//

import Foundation

enum ShardMapRaceOutcome: Sendable {
    case map(ShardMap, index: Int)
    case failed(Error, index: Int, duration: TimeInterval)
    case delayElapsed
}

struct ShardMapRaceArbiter {
    enum Decision: Equatable {
        case wait
        case win(ShardMap, index: Int)
        case fail
    }

    /// The loader's state, to judge whether refresh() would adopt a map.
    private let highestVersion: Int?
    private let hasCurrentMap: Bool
    private var pending: Int
    /// Whether a useful mirror map must still wait for the primary. Ends when
    /// the delay elapses or the primary fails or serves an outdated map; the
    /// race starts any not-yet-started mirrors then.
    private(set) var primaryHasPriority = true
    private var heldMirror: (map: ShardMap, index: Int)?

    /// - sourceCount: how many sources race. Index 0 is the primary; the rest
    ///   are mirrors.
    /// - highestVersion, hasCurrentMap: the loader's current state.
    init(sourceCount: Int, highestVersion: Int?, hasCurrentMap: Bool) {
        self.highestVersion = highestVersion
        self.hasCurrentMap = hasCurrentMap
        self.pending = sourceCount
    }

    private func wouldAdopt(_ map: ShardMap) -> Bool {
        ShardMapLoader.wouldAdopt(version: map.version, hasCurrentMap: hasCurrentMap,
                                  highestVersion: highestVersion)
    }

    /// Why the map source `index` served is no use, or nil if it can win. Only
    /// the arbiter can tell that such a fetch, which succeeded, failed.
    func rejection(of map: ShardMap, from index: Int) -> ShardMapLoaderError? {
        if wouldAdopt(map) {
            return nil
        }
        // With a map loaded, the primary is the truth even when not newer, and
        // a mirror serving the loaded version again is as good as the primary's
        // same answer: nothing changed, so there is nothing to adopt.
        if hasCurrentMap && (index == 0 || map.version == highestVersion) {
            return nil
        }
        return .outdatedMap(served: map.version, latestSeen: highestVersion ?? map.version)
    }

    mutating func handle(_ outcome: ShardMapRaceOutcome) -> Decision {
        switch outcome {
        case let .map(map, index):
            pending -= 1
            if rejection(of: map, from: index) != nil {
                if index == 0 {
                    primaryHasPriority = false
                }
            } else if index == 0 {
                // A primary that has nothing new loses to a held mirror map
                // that does: a lagging edge served the primary's answer.
                if !wouldAdopt(map), let heldMirror, wouldAdopt(heldMirror.map) {
                    return .win(heldMirror.map, index: heldMirror.index)
                }
                return .win(map, index: index)
            } else if !primaryHasPriority {
                return .win(map, index: index)
            } else if map.version > heldMirror?.map.version ?? Int.min {
                heldMirror = (map, index)
            }
        case let .failed(_, index, _):
            pending -= 1
            if index == 0 {
                primaryHasPriority = false
            }
        case .delayElapsed:
            primaryHasPriority = false
        }
        if !primaryHasPriority, let heldMirror {
            return .win(heldMirror.map, index: heldMirror.index)
        }
        return pending == 0 ? .fail : .wait
    }
}
