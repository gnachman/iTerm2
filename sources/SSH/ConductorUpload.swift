import Foundation

// Bound each request so terminal input can be serviced between chunks. Waiting
// for an acknowledgement per KiB makes upload speed depend almost entirely on RTT.
@MainActor
enum ConductorUpload {
    // 16 KiB balances round trips against the framer’s line parsing overhead.
    static let chunkSize = 16 * 1024

    static func send(_ data: Data,
                     checkCancellation: () throws -> Void,
                     append: (Data) async throws -> Void,
                     didTransfer: (Int) -> Void) async throws {
        try checkCancellation()
        var offset = 0
        while offset < data.count {
            try checkCancellation()
            let end = offset + min(chunkSize, data.count - offset)
            let chunk = data.subdata(in: offset..<end)
            try await append(chunk)
            // Cancellation during the final request must be observed too.
            try checkCancellation()
            didTransfer(chunk.count)
            offset = end
        }
    }
}

// Picks the remote name for an upload, never one that exists on the far host or that another
// upload in flight on the same connection has already claimed. Uploads in a batch run
// concurrently, so without the claims two files named x.txt would each find x.txt free and the
// second would overwrite the first. A claim lasts until the caller releases it, which it does once
// the file is in place under that name (and so visible to the existence check) or has failed.
@MainActor
final class ConductorUploadNameReservations {
    private(set) var reserved = Set<String>()
    // Bumped on every release. A release means a file may have just been put in place under that
    // name, so an existence check that was in flight across one may be stale.
    private var releases = 0

    // `exists` reports whether a path is present on the remote host. Returns nil if no free name
    // turned up within the attempt limit.
    func reserve(base: String,
                 maxAttempts: Int = 100,
                 exists: (String) async throws -> Bool) async throws -> String? {
        var i = 0
        var attempts = 0
        while i < maxAttempts && attempts < maxAttempts * 10 {
            attempts += 1
            let proposedName = i == 0 ? base : base + " (\(i + 1))"
            if reserved.contains(proposedName) {
                i += 1
                continue
            }
            let releasesBefore = releases
            let taken = try await exists(proposedName)
            if releases != releasesBefore {
                // Another upload may have placed this name while we awaited. Ask again.
                continue
            }
            // Check again: another upload may have claimed it while we awaited.
            if !taken && !reserved.contains(proposedName) {
                reserved.insert(proposedName)
                return proposedName
            }
            i += 1
        }
        return nil
    }

    func release(_ name: String) {
        reserved.remove(name)
        releases += 1
    }
}
