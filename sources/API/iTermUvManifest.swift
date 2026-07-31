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

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = components(lhs)
        let b = components(rhs)
        let count = max(a.count, b.count)
        for i in 0..<count {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x < y { return .orderedAscending }
            if x > y { return .orderedDescending }
        }
        return .orderedSame
    }
}

struct iTermUvManifestEntry: Equatable, Codable {
    let uvVersion: String
    let url: String
    let signature: String                  // base64 RSA-SHA256 signature over the bytes
    let size: Int
    let minimumMacOSVersion: String        // inclusive lower bound, e.g. "13.0"
    let maximumMacOSVersion: String?       // inclusive upper bound; nil = unbounded

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
    // Decode the manifest JSON array. Returns nil on any malformed input.
    static func parse(_ data: Data) -> [iTermUvManifestEntry]? {
        return try? JSONDecoder().decode([iTermUvManifestEntry].self, from: data)
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
                atMostMax = iTermDottedVersion.compare(runningMacOSVersion, maximum) != .orderedDescending
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
