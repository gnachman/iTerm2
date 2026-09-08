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
