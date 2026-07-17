//
//  CompanionLogArchive.swift
//  CompanionCore
//
//  Bundles the diagnostic log files into a single .zip so they can be emailed as
//  one attachment instead of many. Several multi-megabyte text files attached
//  separately exceed the mail composer's limits; one compressed archive gets
//  through.
//
//  The zipping is done by the system, not by hand: NSFileCoordinator's
//  `.forUploading` read intent hands back a temporary .zip of a directory - the
//  same code path the Files app "Compress" and the share sheet use. It needs no
//  third-party dependency and produces a standard, universally openable .zip.
//  Because the logs live in two directories (the app's and the NSE's), we first
//  stage them into one folder, which also makes the archive extract to a single
//  tidy folder.
//
//  Building is split into two phases on purpose:
//   * `stage` is FAST (hard links, no byte copy) and side-effect-free on the
//     sources, so the caller can run it on the log queue to snapshot the files
//     atomically against a concurrent delete-all (toggling logging off). Hard
//     links keep each file's data alive even if the original is removed right
//     after staging, so the snapshot can't be torn out from under the zip.
//   * `zip` is the SLOW DEFLATE pass and runs off the log queue.
//

import Foundation

public enum CompanionLogArchive {
    public enum ArchiveError: Error {
        /// None of the input files could be staged, so there is nothing to zip.
        case nothingToArchive
        /// The system coordinator returned without producing an archive.
        case zipFailed
    }

    /// Stage `files` into a fresh temp directory and return that directory,
    /// ready to hand to `zip`. Each file is hard-linked (O(1), no byte copy;
    /// falls back to a real copy across volumes) under a folder named
    /// `folderName`, so the eventual archive extracts to one tidy folder.
    /// Basename collisions are disambiguated so no file is dropped. Throws
    /// `.nothingToArchive` if nothing could be staged. FAST and snapshotting:
    /// once this returns, the staged links survive deletion of the originals.
    public static func stage(files: [URL], folderName: String) throws -> URL {
        let fm = FileManager.default
        // The `wrapper` level keeps everything we create under one subtree the
        // caller (via `zip`) can delete afterward; `staging` is the folder
        // NSFileCoordinator will actually zip.
        let wrapper = fm.temporaryDirectory
            .appendingPathComponent("logzip-\(UUID().uuidString)", isDirectory: true)
        let staging = wrapper.appendingPathComponent(folderName, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        var staged = 0
        for url in files {
            // Disambiguate on a basename collision rather than let the link/copy
            // throw (which `try?` would swallow, silently dropping the file). Two
            // logs can share a name: legacy unlabeled files (bare timestamp, no
            // -app/-nse suffix) left by an older build in both the app and NSE
            // directories at the same second.
            let target = uniqueDestination(for: url.lastPathComponent, in: staging, fm: fm)
            // Prefer a hard link so a large history is not duplicated on disk and
            // the staged entry outlives the original's deletion; fall back to a
            // real copy when the link fails (e.g. EXDEV across volumes).
            if (try? fm.linkItem(at: url, to: target)) != nil
                || (try? fm.copyItem(at: url, to: target)) != nil {
                staged += 1
            }
        }
        guard staged > 0 else {
            try? fm.removeItem(at: wrapper)
            throw ArchiveError.nothingToArchive
        }
        return staging
    }

    /// Zip a directory produced by `stage` into `destination` (the slow DEFLATE
    /// pass), then delete the staging subtree. Any prior archive at
    /// `destination` is cleared first, so a failure never leaves a stale zip.
    public static func zip(stagedDirectory: URL, to destination: URL) throws {
        let fm = FileManager.default
        defer { try? fm.removeItem(at: stagedDirectory.deletingLastPathComponent()) }
        try? fm.removeItem(at: destination)

        var coordinatorError: NSError?
        var accessorError: Error?
        NSFileCoordinator().coordinate(readingItemAt: stagedDirectory,
                                       options: [.forUploading],
                                       error: &coordinatorError) { zipURL in
            // zipURL is only valid inside this block; copy it out before returning.
            do { try fm.copyItem(at: zipURL, to: destination) }
            catch { accessorError = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let accessorError { throw accessorError }
        guard fm.fileExists(atPath: destination.path) else { throw ArchiveError.zipFailed }
    }

    /// Stage then zip in one call. Convenience for callers that don't need to
    /// serialize staging against a concurrent deletion (tests, and any use where
    /// the sources can't disappear mid-build). Each file is placed under a
    /// top-level folder named after `destination` (minus the .zip extension).
    /// Throws `.nothingToArchive` if nothing could be staged; on success
    /// `destination` exists and is a valid .zip.
    public static func write(files: [URL], to destination: URL) throws {
        // Clear any prior archive up front so even a `.nothingToArchive` throw
        // (which happens before `zip` runs) can't leave a stale zip behind.
        try? FileManager.default.removeItem(at: destination)
        let folderName = destination.deletingPathExtension().lastPathComponent
        let staged = try stage(files: files, folderName: folderName)
        try zip(stagedDirectory: staged, to: destination)
    }

    /// A URL in `directory` for `name` that does not yet exist, appending a
    /// counter before the extension on collision (`log.txt` -> `log-2.txt`), so
    /// two inputs sharing a basename both make it into the archive. The staging
    /// directory is created empty and only written here, so no external writer
    /// can race the existence check.
    private static func uniqueDestination(for name: String, in directory: URL, fm: FileManager) -> URL {
        let candidate = directory.appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var counter = 2
        while true {
            let disambiguated = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            let url = directory.appendingPathComponent(disambiguated)
            if !fm.fileExists(atPath: url.path) { return url }
            counter += 1
        }
    }
}
