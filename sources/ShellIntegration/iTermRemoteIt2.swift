//
//  iTermRemoteIt2.swift
//  iTerm2SharedARC
//
//  The it2 CLI as it is delivered to a remote host: a hash-named copy of the
//  bundled interpreter plus the wrapper that execs it.
//
//  The shell-integration scripts already materialize their embedded copy to
//  ~/.iterm2/it2.<hash>.py, so the upload uses that same name and the two
//  mechanisms agree instead of writing competing files. The bundle cannot hold
//  that name, because it changes with every edit to it2.py and each change
//  would need a fresh Xcode file reference; TarJob takes a remote entry's name
//  from the source's path relative to its local base, so a hash-named copy made
//  on the way out gives the right remote name while the bundle keeps one stable
//  it2.py.
//

import Foundation

@objc(iTermRemoteIt2)
class iTermRemoteIt2: NSObject {
    /// The hash of the bundled it2.py, substituted at build time by
    /// tools/copy_shell_integration.sh (see iTermBundledIt2.swift).
    @objc static var bundledPyHash: String {
        return iTermBundledIt2PyHash
    }

    /// Where the wrapper looks for the interpreter when no IT2_PY was injected, and where the
    /// upload puts it. Matches what the shell-integration scripts materialize.
    @objc static func remotePyPath(home: String, hash: String) -> String {
        return "\(home)/.iterm2/it2.\(hash).py"
    }

    /// Where hash-named copies are staged before upload: a subdirectory of THIS instance's dot
    /// dir, which is per-suite, always writable by the user, and not world-readable.
    ///
    /// Deliberately not /tmp. It is shared by every user on the machine, so a copy there leaks
    /// what is being uploaded on a multi-user box, and it is not reliably writable in the first
    /// place. The dot dir is where iTerm2's other per-user artifacts already live.
    @objc static func stagingDirectory() -> URL? {
        guard let dotDir = FileManager.default.homeDirectoryDotDir() else {
            return nil
        }
        return URL(fileURLWithPath: dotDir).appendingPathComponent("remote-it2")
    }

    /// The bundled it2.py staged under its content-hashed remote name, ready for a payload
    /// builder, or nil when it cannot be produced.
    @objc static func stagedBundledCopy() -> URL? {
        guard let staging = stagingDirectory() else {
            RLog("No dot dir, so it2 cannot be staged for upload")
            return nil
        }
        guard let bundled = Bundle(for: PTYSession.self).path(forResource: "it2", ofType: "py") else {
            RLog("it2.py is not in the bundle; the remote host will not get it2")
            return nil
        }
        return hashedCopyURL(source: URL(fileURLWithPath: bundled),
                             hash: bundledPyHash,
                             cacheDirectory: staging)
    }

    /// The wrapper staged under the name it must have on the remote host.
    ///
    /// TarJob takes a remote entry's name from the local basename, and the bundle resource is
    /// called it2-remote to keep it distinct from the it2 CLI we build for the Mac. It has to
    /// land as ~/.iterm2/bin/it2, so it is staged as "it2" first.
    @objc static func stagedWrapper(source: URL) -> URL? {
        guard let staging = stagingDirectory() else {
            return nil
        }
        let destination = staging.appendingPathComponent("bin").appendingPathComponent("it2")
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: destination.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            // Always refresh: unlike the interpreter, the wrapper is not content-addressed, so a
            // stale one from a previous build would name the wrong interpreter forever.
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: source, to: destination)
            // tar xpzf under umask 000 preserves the mode, so the bit has to be right here.
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
            return destination
        } catch {
            RLog("Could not stage the it2 wrapper for upload: \(error)")
            return nil
        }
    }

    /// A copy of `source` named it2.<hash>.py, suitable for handing to a payload builder.
    /// Returns nil when the source cannot be read.
    ///
    /// Reused when it already exists: this runs once per connection, and rewriting a file the
    /// previous connection is still uploading would be pointless churn. Copies for other hashes
    /// are deliberately left alone, since two iTerm2 builds can be uploading to the same host
    /// and each needs its own.
    @objc static func hashedCopyURL(source: URL, hash: String, cacheDirectory: URL) -> URL? {
        let destination = cacheDirectory.appendingPathComponent("it2.\(hash).py")
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            return destination
        }
        guard fm.fileExists(atPath: source.path) else {
            RLog("Bundled it2.py missing at \(source.path); the remote host will not get it2")
            return nil
        }
        do {
            try fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            // Write through a temporary name IN THE SAME DIRECTORY and move into place, so a
            // second connection uploading at the same time never sees a half-written
            // interpreter, and so the rename is on one filesystem. Never /tmp: see
            // stagingDirectory().
            let temporary = cacheDirectory.appendingPathComponent("it2.\(hash).py.\(UUID().uuidString)")
            try fm.copyItem(at: source, to: temporary)
            do {
                try fm.moveItem(at: temporary, to: destination)
            } catch {
                try? fm.removeItem(at: temporary)
                // Lost the race: the other writer's copy is the same content, so use it.
                guard fm.fileExists(atPath: destination.path) else {
                    throw error
                }
            }
            return destination
        } catch {
            RLog("Could not stage it2.py for upload: \(error)")
            return nil
        }
    }
}
