//
//  iTermUvPythonVersion.swift
//  iTerm2SharedARC
//
//  Phase 2/3 of the uv Python-runtime migration. Resolves the Python version a
//  script should actually run under. python-build-standalone offers 3.8+, so the
//  pinned minor is preserved whenever available; a version it cannot provide (in
//  practice 3.7 and older) is bumped to a safe target (3.9, the last release before
//  the 3.10 collections.abc alias removal). A non-nil remappedFrom means the user
//  must be told the version changed. See docs/uv-python-runtime-migration.md.
//

import Foundation

struct iTermUvResolvedPythonVersion: Equatable {
    let version: String        // two-part minor to hand to uv, e.g. "3.9"
    let remappedFrom: String?  // the original pin if it was bumped; nil if preserved
}

enum iTermUvPythonVersion {
    // The safe landing spot for versions python-build-standalone cannot provide.
    static let safeFallbackVersion = "3.9"

    private struct ListEntry: Decodable {
        let version: String
        let implementation: String?
        let variant: String?
    }

    // A stable version string is only digits and dots (e.g. "3.14.0"), excluding
    // pre-releases like "3.15.0a2".
    static func isStableVersion(_ version: String) -> Bool {
        return !version.isEmpty && version.allSatisfy { $0.isNumber || $0 == "." }
    }

    // Parse `uv python list --output-format json` into the sorted, unique set of
    // stable CPython (default variant) minor versions uv can provide.
    static func availableMinors(fromListJSON data: Data) -> [String] {
        guard let entries = try? JSONDecoder().decode([ListEntry].self, from: data) else {
            return []
        }
        var minors = Set<String>()
        for entry in entries {
            guard (entry.implementation ?? "cpython") == "cpython",
                  (entry.variant ?? "default") == "default",
                  isStableVersion(entry.version) else {
                continue
            }
            minors.insert(twoPartVersion(entry.version))
        }
        return minors.sorted { iTermDottedVersion.compare($0, $1) == .orderedAscending }
    }

    static func twoPartVersion(_ version: String) -> String {
        let parts = version.split(separator: ".")
        if parts.count >= 2 {
            return "\(parts[0]).\(parts[1])"
        }
        return version
    }

    static func resolve(requested: String, available: [String]) -> iTermUvResolvedPythonVersion {
        let requestedMinor = twoPartVersion(requested)

        // If uv python list failed, don't invent a version; keep the pin as-is.
        if available.isEmpty {
            return iTermUvResolvedPythonVersion(version: requestedMinor, remappedFrom: nil)
        }
        // Preserve the pinned minor whenever it is available (silent, no bump).
        if available.contains(requestedMinor) {
            return iTermUvResolvedPythonVersion(version: requestedMinor, remappedFrom: nil)
        }
        // Prefer the safe fallback, but only if it is at least the requested minor
        // (never downgrade a script that pinned something newer).
        if available.contains(safeFallbackVersion),
           iTermDottedVersion.compare(safeFallbackVersion, requestedMinor) != .orderedAscending {
            return iTermUvResolvedPythonVersion(version: safeFallbackVersion, remappedFrom: requested)
        }
        // Otherwise the nearest available minor at or above the requested one.
        let forward = available
            .filter { iTermDottedVersion.compare($0, requestedMinor) != .orderedAscending }
            .sorted { iTermDottedVersion.compare($0, $1) == .orderedAscending }
        if let nearest = forward.first {
            return iTermUvResolvedPythonVersion(version: nearest, remappedFrom: requested)
        }
        // The pin is newer than everything available: land on the newest.
        let newest = available.max { iTermDottedVersion.compare($0, $1) == .orderedAscending } ?? requestedMinor
        return iTermUvResolvedPythonVersion(version: newest, remappedFrom: requested)
    }
}
