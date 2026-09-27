//
//  iTermUvManifest.swift
//  iTerm2SharedARC
//
//  Phase 1 of the uv Python-runtime migration. Models the uv download manifest
//  and selects the newest uv build compatible with the running macOS. Each entry
//  is bracketed by a min/max macOS version so that a future uv which raises its
//  macOS floor is simply never offered to users on an older macOS, rather than
//  stranding them on an unlaunchable download. See
//  docs/uv-python-runtime-migration.md (Phase 1).
//

import Foundation

// Compares dotted numeric version strings ("0.12.0", "13.4"). We use a small,
// self-contained comparator rather than Sparkle's SUStandardVersionComparator
// because the latter has no Swift call sites in this project (reaching it would
// require an unverified Sparkle-from-Swift import) and manifest/OS versions need
// only simple numeric-dotted semantics that are trivial to unit-test.
enum iTermDottedVersion {
    // Numeric components; non-numeric or missing components are treated as 0.
    static func components(_ string: String) -> [Int] {
        return string.split(separator: ".").map { Int($0) ?? 0 }
    }

    static func compare(_ lhs: [Int], _ rhs: [Int]) -> ComparisonResult {
        let count = max(lhs.count, rhs.count)
        for i in 0..<count {
            let x = i < lhs.count ? lhs[i] : 0
            let y = i < rhs.count ? rhs[i] : 0
            if x < y { return .orderedAscending }
            if x > y { return .orderedDescending }
        }
        return .orderedSame
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        return compare(components(lhs), components(rhs))
    }
}

struct iTermUvManifestEntry: Equatable, Codable {
    let uvVersion: String
    let url: String
    let signature: String                  // base64 RSA-SHA256 signature over the bytes
    let size: Int
    let minimumMacOSVersion: String        // inclusive lower bound, e.g. "13.0"
    let maximumMacOSVersion: String?       // inclusive family cap at the given precision
                                           // (e.g. "13.4" caps all of 13.4.x); nil = unbounded

    enum CodingKeys: String, CodingKey {
        case uvVersion = "uv_version"
        case url
        case signature
        case size
        case minimumMacOSVersion = "minimum_macos_version"
        case maximumMacOSVersion = "maximum_macos_version"
    }
}

enum iTermUvManifest {
    // Wraps an entry so one undecodable element does not fail the whole array. The
    // initializer never throws: an entry this build cannot decode becomes nil.
    private struct FailableEntry: Decodable {
        let entry: iTermUvManifestEntry?
        init(from decoder: Decoder) throws {
            entry = try? iTermUvManifestEntry(from: decoder)
        }
    }

    // Decode the manifest JSON array, tolerantly and per entry. The manifest is
    // updated annually and already-shipped clients must keep working against future
    // manifests, so a single future entry with an unfamiliar shape (a missing or
    // renamed field, a retyped value) must not discard the entire manifest and
    // strand shipped builds that a still-compatible entry serves. Undecodable
    // entries are skipped; the rest are kept. Returns nil only when the top level is
    // not a JSON array at all.
    static func parse(_ data: Data) -> [iTermUvManifestEntry]? {
        guard let wrapped = try? JSONDecoder().decode([FailableEntry].self, from: data) else {
            return nil
        }
        return wrapped.compactMap { $0.entry }
    }

    // The newest uv build whose macOS bracket includes the running OS, or nil if
    // none qualifies. "Newest" is by uv version, so manifest ordering does not
    // matter.
    static func select(entries: [iTermUvManifestEntry],
                       runningMacOSVersion: String) -> iTermUvManifestEntry? {
        let compatible = entries.filter { entry in
            let atLeastMin = iTermDottedVersion.compare(runningMacOSVersion,
                                                        entry.minimumMacOSVersion) != .orderedAscending
            let atMostMax: Bool
            if let maximum = entry.maximumMacOSVersion {
                // Treat the maximum as a family cap at the precision the manifest
                // provides: a cap of "13.4" bounds the whole 13.4.x family (so 13.4.1
                // is still included), and "13" bounds all of 13.x. Comparing the full
                // three-part running version against a two-part cap would wrongly
                // exclude every later point release of the capped family (13.4.1 >
                // 13.4.0). So compare only as many leading components as the cap gives.
                let maxComponents = iTermDottedVersion.components(maximum)
                let runningComponents = Array(iTermDottedVersion.components(runningMacOSVersion).prefix(maxComponents.count))
                atMostMax = iTermDottedVersion.compare(runningComponents, maxComponents) != .orderedDescending
            } else {
                atMostMax = true
            }
            return atLeastMin && atMostMax
        }
        return compatible.max { lhs, rhs in
            iTermDottedVersion.compare(lhs.uvVersion, rhs.uvVersion) == .orderedAscending
        }
    }
}
