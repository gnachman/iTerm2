//
//  ConductorPayloadBuilder.swift
//  iTerm2
//
//  Created by George Nachman on 7/1/25.
//

class ConductorPayloadBuilder {
    private var tarJobs = [TarJob]()
    /// Remote paths already queued, so a duplicate cannot be tarred twice.
    private var queuedRemotePaths = Set<String>()

    /// Queue a file for upload. A source that does not exist is dropped here rather than at tar
    /// time, and a second file that would land on the same remote path is ignored.
    ///
    /// Both matter because payload paths are persisted in restorable state, so a session can
    /// still be carrying the previous build's content-hashed it2 path after an upgrade. A TarJob
    /// tars all of its sources together, so without this one stale entry makes tarballData()
    /// throw and silently suppresses the entire shell-integration upload for that session.
    func add(localPath: URL, destination: URL) {
        guard FileManager.default.fileExists(atPath: localPath.path) else {
            DLog("Payload source missing, skipping: \(localPath.path)")
            return
        }
        // The remote name is the local basename, so two sources with the same basename and the
        // same destination would collide inside one tarball. First one wins.
        let remotePath = destination.appendingPathComponent(localPath.lastPathComponent).path
        guard !queuedRemotePaths.contains(remotePath) else {
            DLog("Payload already queued for \(remotePath), skipping \(localPath.path)")
            return
        }
        queuedRemotePaths.insert(remotePath)
        for (i, _) in tarJobs.enumerated() {
            if tarJobs[i].add(local: localPath, destination: destination) {
                return
            }
        }
        tarJobs.append(TarJob(local: localPath, destination: destination))
    }

    func enumeratePayloads(_ closure: (Data, String) -> ()) {
        for job in tarJobs {
            if let data = try? job.tarballData() {
                closure(data, job.destinationBase.path)
            } else {
                RLog("Failed to build a tarball for \(job.destinationBase.path); its files will be missing on the remote host")
            }
        }
    }

    /// How many sources are queued for a destination. For tests.
    func sourceCount(forDestination destination: String) -> Int {
        return tarJobs.filter { $0.destinationBase.path == destination }
            .reduce(0) { $0 + $1.sources.count }
    }
}
