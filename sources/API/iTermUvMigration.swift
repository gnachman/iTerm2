//
//  iTermUvMigration.swift
//  iTerm2SharedARC
//
//  Phase 3 of the uv Python-runtime migration. Pure logic for migrating existing
//  legacy full-environment scripts to uv: which scripts must have their pinned
//  Python version bumped (only versions python-build-standalone cannot provide, in
//  practice 3.7 -> 3.9), and the one consolidated, suppressible warning that tells
//  the user. See docs/uv-python-runtime-migration.md (Phase 3).
//

import Foundation

@objc(iTermUvPythonRemap)
class iTermUvPythonRemap: NSObject {
    @objc let scriptName: String
    @objc let fromVersion: String
    @objc let toVersion: String

    @objc init(scriptName: String, fromVersion: String, toVersion: String) {
        self.scriptName = scriptName
        self.fromVersion = fromVersion
        self.toVersion = toVersion
    }
}

@objc(iTermUvMigration)
class iTermUvMigration: NSObject {
    // Given each script's pinned Python version and the minors uv can provide,
    // return the scripts whose version must be bumped (a preserved minor is silent
    // and omitted). Sorted by script name for a stable, consolidated warning.
    @objc static func forcedRemaps(requestedVersionsByScript: [String: String],
                                   available: [String]) -> [iTermUvPythonRemap] {
        var remaps: [iTermUvPythonRemap] = []
        for (name, requested) in requestedVersionsByScript {
            let resolved = iTermUvPythonVersion.resolve(requested: requested, available: available)
            if let from = resolved.remappedFrom {
                remaps.append(iTermUvPythonRemap(scriptName: name,
                                                 fromVersion: iTermUvPythonVersion.twoPartVersion(from),
                                                 toVersion: resolved.version))
            }
        }
        return remaps.sorted { $0.scriptName.localizedCaseInsensitiveCompare($1.scriptName) == .orderedAscending }
    }

    // The minors python-build-standalone is known to provide, used for the one-time
    // startup warning scan so it need not invoke uv. The actual migration always
    // re-resolves against live `uv python list`.
    @objc static let knownAvailableMinors = ["3.8", "3.9", "3.10", "3.11", "3.12", "3.13", "3.14"]

    // The one consolidated warning to show once at startup for un-migrated legacy
    // scripts whose pinned Python version will be bumped, or nil if none will be.
    @objc static func pendingVersionBumpWarning(requestedVersionsByScript: [String: String]) -> String? {
        let remaps = forcedRemaps(requestedVersionsByScript: requestedVersionsByScript,
                                  available: knownAvailableMinors)
        return remaps.isEmpty ? nil : consolidatedWarningText(remaps: remaps)
    }

    // The one warning shown when migration bumps script Python versions. Empty if
    // nothing was bumped.
    @objc static func consolidatedWarningText(remaps: [iTermUvPythonRemap]) -> String {
        guard !remaps.isEmpty else {
            return ""
        }
        let caveat = "Python versions are not always compatible across releases, so a bumped script may need small changes."
        if remaps.count == 1, let only = remaps.first {
            return "The script “\(only.scriptName)” was written for Python \(only.fromVersion), "
                + "which is no longer available, so it now uses Python \(only.toVersion). "
                + caveat
        }
        let lines = remaps.map { "• “\($0.scriptName)”: \($0.fromVersion) → \($0.toVersion)" }
        return "Some scripts were written for Python versions that are no longer available "
            + "and now use newer ones. " + caveat + "\n\n"
            + lines.joined(separator: "\n")
    }

    // MARK: - Rebuild-with-rollback file operations

    // These move the user's existing legacy environment aside so a failed uv
    // migration can be fully undone. They never delete the legacy iterm2env until
    // the uv .venv is in place, so a crash mid-migration leaves a recoverable state.

    private static func savedPath(_ container: String) -> String {
        return (container as NSString).appendingPathComponent("saved-iterm2env")
    }

    private static func legacyPath(_ container: String) -> String {
        return (container as NSString).appendingPathComponent(iTermScriptRuntime.legacyDirectoryName)
    }

    private static func venvPath(_ container: String) -> String {
        return (container as NSString).appendingPathComponent(iTermScriptRuntime.venvDirectoryName)
    }

    private static func markerPath(_ container: String) -> String {
        return (container as NSString).appendingPathComponent(iTermScriptRuntime.markerFileName)
    }

    // Move iterm2env aside to saved-iterm2env before provisioning the uv .venv.
    // Crash-safe: if a previous migration was interrupted after the backup but before
    // the .venv was finished (backup present, no legacy env), the backup IS the
    // user's only environment, so recover it rather than deleting it. saved-iterm2env
    // is only ever removed when a legacy env exists to immediately replace it.
    @objc static func backUpLegacyEnvironment(container: String) throws {
        let fm = FileManager.default
        let saved = savedPath(container)
        let legacy = legacyPath(container)

        // Recover an orphaned backup from an interrupted prior migration.
        if fm.fileExists(atPath: saved) && !fm.fileExists(atPath: legacy) {
            try fm.moveItem(atPath: saved, toPath: legacy)
        }
        // Discard any partial uv artifacts from an interrupted prior attempt so the
        // re-provision starts clean.
        for partial in [venvPath(container), markerPath(container)] where fm.fileExists(atPath: partial) {
            try fm.removeItem(atPath: partial)
        }
        // Back up the legacy env. Removing a stale saved is safe here because a legacy
        // env exists to repopulate it.
        if fm.fileExists(atPath: legacy) {
            if fm.fileExists(atPath: saved) {
                try fm.removeItem(atPath: saved)
            }
            try fm.moveItem(atPath: legacy, toPath: saved)
        }
    }

    // Undo a failed migration: remove any partial uv artifacts and restore the
    // legacy environment from the backup.
    @objc static func restoreLegacyEnvironment(container: String) throws {
        let fm = FileManager.default
        for partial in [venvPath(container), markerPath(container)] where fm.fileExists(atPath: partial) {
            try fm.removeItem(atPath: partial)
        }
        let saved = savedPath(container)
        if fm.fileExists(atPath: saved) {
            let legacy = legacyPath(container)
            if fm.fileExists(atPath: legacy) {
                try fm.removeItem(atPath: legacy)
            }
            try fm.moveItem(atPath: saved, toPath: legacy)
        }
    }

    // Migration succeeded: drop the backup.
    @objc static func discardLegacyBackup(container: String) {
        try? FileManager.default.removeItem(atPath: savedPath(container))
    }
}
