import XCTest
@testable import iTerm2SharedARC

@MainActor
final class ConductorUploadTests: XCTestCase {
    func testScreenshotUsesThirtyOneRequestsAndPreservesBytes() async throws {
        let data = Data((0..<(490 * 1024)).map { UInt8(truncatingIfNeeded: $0) })
        var chunks = [Data]()
        var progress = 0
        try await ConductorUpload.send(data, checkCancellation: {}) { chunk in
            chunks.append(chunk)
        } didTransfer: { count in
            progress += count
        }
        XCTAssertEqual(chunks.count, 31)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 16 * 1024 })
        XCTAssertEqual(chunks.reduce(into: Data()) { $0.append($1) }, data)
        XCTAssertEqual(progress, data.count)
    }

    func testCancellationDuringFinalAppendDoesNotFinishUpload() async {
        var cancelled = false
        var progress = 0
        do {
            try await ConductorUpload.send(Data([1, 2, 3]), checkCancellation: {
                if cancelled { throw CancellationError() }
            }) { _ in
                cancelled = true
            } didTransfer: { progress += $0 }
            XCTFail("Cancellation during the final append must reach the cleanup path")
        } catch is CancellationError {
            XCTAssertEqual(progress, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancellationBetweenChunksDoesNotSendAnotherRequest() async {
        var cancelled = false
        var requests = 0
        do {
            try await ConductorUpload.send(Data(count: 128 * 1024), checkCancellation: {
                if cancelled { throw CancellationError() }
            }) { _ in
                requests += 1
            } didTransfer: { _ in
                cancelled = true
            }
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertEqual(requests, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAppendFailureDoesNotReportProgressOrSendAnotherChunk() async {
        var requests = 0
        var progress = 0
        do {
            try await ConductorUpload.send(Data(count: 128 * 1024), checkCancellation: {}) { _ in
                requests += 1
                throw CocoaError(.fileWriteUnknown)
            } didTransfer: { progress += $0 }
            XCTFail("Expected append error")
        } catch {
            XCTAssertEqual(requests, 1)
            XCTAssertEqual(progress, 0)
        }
    }

    func testEmptyUploadStillChecksCancellation() async {
        do {
            try await ConductorUpload.send(Data(), checkCancellation: {
                throw CancellationError()
            }) { _ in
                XCTFail("Empty upload must not append")
            } didTransfer: { _ in
                XCTFail("Empty upload must not report progress")
            }
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
