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

import Foundation

public enum CompanionLogArchive {
    public enum ArchiveError: Error {
        /// None of the input files could be staged, so there is nothing to zip.
        case nothingToArchive
        /// The system coordinator returned without producing an archive.
        case zipFailed
    }

    /// Write a .zip at `destination` containing `files`, each placed under a
    /// top-level folder named after `destination` (minus the .zip extension).
    /// Files that cannot be read are skipped; if that leaves nothing, throws
    /// `.nothingToArchive`. On success `destination` exists and is a valid .zip.
    public static func write(files: [URL], to destination: URL) throws {
        let fm = FileManager.default
        // Clear any prior archive up front. `makeLogArchive()` reuses one fixed
        // path, so a failure here (including no files to archive) must not leave
        // a stale zip behind for the next caller to attach.
        try? fm.removeItem(at: destination)

        let folderName = destination.deletingPathExtension().lastPathComponent
        // NSFileCoordinator zips the item we point it at, so point it at a single
        // folder. The extra `wrapper` level keeps everything we create under one
        // subtree we can delete afterward.
        let wrapper = fm.temporaryDirectory
            .appendingPathComponent("logzip-\(UUID().uuidString)", isDirectory: true)
        let staging = wrapper.appendingPathComponent(folderName, isDirectory: true)
        // Register cleanup BEFORE createDirectory: it creates the `wrapper`
        // level as an intermediate, so a throw from it would otherwise leak
        // that subtree.
        defer { try? fm.removeItem(at: wrapper) }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        var staged = 0
        for url in files {
            // Disambiguate on a basename collision rather than let copyItem throw
            // (which `try?` would swallow, silently dropping the file). Two logs
            // can share a name: legacy unlabeled files (bare timestamp, no
            // -app/-nse suffix) left by an older build in both the app and NSE
            // directories at the same second.
            let target = uniqueDestination(for: url.lastPathComponent, in: staging, fm: fm)
            if (try? fm.copyItem(at: url, to: target)) != nil { staged += 1 }
        }
        guard staged > 0 else { throw ArchiveError.nothingToArchive }

        var coordinatorError: NSError?
        var accessorError: Error?
        NSFileCoordinator().coordinate(readingItemAt: staging,
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
