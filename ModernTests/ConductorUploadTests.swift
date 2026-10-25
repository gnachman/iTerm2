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

@MainActor
final class ConductorUploadNameReservationsTests: XCTestCase {
    func testFreeNameIsUsedAsIs() async throws {
        let reservations = ConductorUploadNameReservations()
        let name = try await reservations.reserve(base: "/home/u/x.txt") { _ in false }
        XCTAssertEqual(name, "/home/u/x.txt")
    }

    func testExistingNameGetsNumberedSuffix() async throws {
        let reservations = ConductorUploadNameReservations()
        let name = try await reservations.reserve(base: "/home/u/x.txt") { $0 == "/home/u/x.txt" }
        XCTAssertEqual(name, "/home/u/x.txt (2)")
    }

    // Two files with the same basename in one batch: neither is on the remote yet when the names
    // are chosen, so the second must not reuse the first one's name.
    func testSameBasenameInOneBatchGetsDistinctNames() async throws {
        let reservations = ConductorUploadNameReservations()
        let first = try await reservations.reserve(base: "/home/u/x.txt") { _ in false }
        let second = try await reservations.reserve(base: "/home/u/x.txt") { _ in false }
        XCTAssertEqual(first, "/home/u/x.txt")
        XCTAssertEqual(second, "/home/u/x.txt (2)")
    }

    func testSameBasenameInOneBatchWhenNameAlreadyExistsRemotely() async throws {
        let reservations = ConductorUploadNameReservations()
        let exists: (String) async throws -> Bool = { $0 == "/home/u/x.txt" }
        let first = try await reservations.reserve(base: "/home/u/x.txt", exists: exists)
        let second = try await reservations.reserve(base: "/home/u/x.txt", exists: exists)
        XCTAssertEqual(first, "/home/u/x.txt (2)")
        XCTAssertEqual(second, "/home/u/x.txt (3)")
    }

    // Both uploads ask about x.txt before either claims it, as happens when their existence
    // checks are in flight at the same time. The stub holds every check until both have asked,
    // so the interleaving does not depend on scheduling.
    func testConcurrentReservationsWhoseChecksInterleaveGetDistinctNames() async throws {
        let reservations = ConductorUploadNameReservations()
        var waiters = [CheckedContinuation<Void, Never>]()
        var asked = [String]()
        let exists: (String) async throws -> Bool = { path in
            asked.append(path)
            if asked.count < 2 {
                await withCheckedContinuation { waiters.append($0) }
            } else {
                waiters.forEach { $0.resume() }
                waiters.removeAll()
            }
            return false
        }
        async let a = reservations.reserve(base: "/home/u/x.txt", exists: exists)
        async let b = reservations.reserve(base: "/home/u/x.txt", exists: exists)
        let names = try await [a, b]
        XCTAssertEqual(asked.prefix(2), ["/home/u/x.txt", "/home/u/x.txt"])
        XCTAssertEqual(Set(names.compactMap { $0 }), ["/home/u/x.txt", "/home/u/x.txt (2)"])
    }

    // B's check of x.txt is in flight while A claims x.txt, moves its file into place, and
    // releases the claim. B's answer of "free" is stale by then, so B must not take x.txt.
    func testStaleCheckAfterAnotherUploadPlacedTheFileIsRetried() async throws {
        let reservations = ConductorUploadNameReservations()
        var placed = Set<String>()
        var heldCheck: CheckedContinuation<Bool, Never>?
        var checkStarted: CheckedContinuation<Void, Never>?
        var holdNextCheck = true
        let exists: (String) async throws -> Bool = { path in
            if holdNextCheck {
                holdNextCheck = false
                return await withCheckedContinuation { continuation in
                    heldCheck = continuation
                    checkStarted?.resume()
                    checkStarted = nil
                }
            }
            return placed.contains(path)
        }
        var b: Task<String?, Error>?
        await withCheckedContinuation { started in
            checkStarted = started
            b = Task { @MainActor in
                try await reservations.reserve(base: "/home/u/x.txt", exists: exists)
            }
        }
        let a = try await reservations.reserve(base: "/home/u/x.txt", exists: exists)
        XCTAssertEqual(a, "/home/u/x.txt")
        placed.insert(a!)
        reservations.release(a!)
        // Answer B's held check as it would have been answered when it was sent.
        heldCheck!.resume(returning: false)
        let bName = try await b!.value
        XCTAssertEqual(bName, "/home/u/x.txt (2)")
    }

    func testReleasedNameCanBeChosenAgain() async throws {
        let reservations = ConductorUploadNameReservations()
        let first = try await reservations.reserve(base: "/home/u/x.txt") { _ in false }
        reservations.release(first!)
        let second = try await reservations.reserve(base: "/home/u/x.txt") { _ in false }
        XCTAssertEqual(second, "/home/u/x.txt")
    }

    func testGivesUpAfterMaxAttempts() async throws {
        let reservations = ConductorUploadNameReservations()
        let name = try await reservations.reserve(base: "/home/u/x.txt", maxAttempts: 3) { _ in true }
        XCTAssertNil(name)
        XCTAssertTrue(reservations.reserved.isEmpty)
    }
}

// Picking an upload's remote name from stat results. Only a definite "not found" may count as a
// free name; any other failure must stop the upload rather than risk overwriting a file.
@MainActor
final class ConductorUploadRemoteNameCheckTests: XCTestCase {
    private enum FakeRemote {
        case exists
        case notFound
        case failure(Error)
    }

    private func stat(_ remote: [String: FakeRemote]) -> (String) async throws -> Void {
        return { path in
            switch remote[path] ?? .notFound {
            case .exists:
                return
            case .notFound:
                throw SSHEndpointException.fileNotFound
            case .failure(let error):
                throw error
            }
        }
    }

    private func pickName(_ remote: [String: FakeRemote]) async throws -> String? {
        let reservations = ConductorUploadNameReservations()
        let stat = stat(remote)
        return try await reservations.reserve(base: "/home/u/x.txt") { path in
            try await ConductorUpload.remotePathExists(path, stat: stat)
        }
    }

    func testNotFoundIsFree() async throws {
        let name = try await pickName([:])
        XCTAssertEqual(name, "/home/u/x.txt")
    }

    func testExistingFileIsSkipped() async throws {
        let name = try await pickName(["/home/u/x.txt": .exists])
        XCTAssertEqual(name, "/home/u/x.txt (2)")
    }

    func testPermissionErrorFailsInsteadOfChoosingTheName() async throws {
        do {
            let name = try await pickName(["/home/u/x.txt": .failure(SSHEndpointException.fileOperationFailed)])
            XCTFail("Expected an error, got \(String(describing: name))")
        } catch let error as ConductorUpload.NameCheckFailed {
            XCTAssertEqual(error.path, "/home/u/x.txt")
        }
    }

    func testConnectionErrorFailsInsteadOfChoosingTheName() async throws {
        do {
            let name = try await pickName(["/home/u/x.txt": .exists,
                                           "/home/u/x.txt (2)": .failure(SSHEndpointException.connectionClosed)])
            XCTFail("Expected an error, got \(String(describing: name))")
        } catch let error as ConductorUpload.NameCheckFailed {
            XCTAssertEqual(error.path, "/home/u/x.txt (2)")
            XCTAssertTrue(error.localizedDescription.contains("x.txt (2)"))
        }
    }

    func testFailedCheckLeavesNoReservation() async throws {
        let reservations = ConductorUploadNameReservations()
        let stat = stat(["/home/u/x.txt": .failure(SSHEndpointException.connectionClosed)])
        _ = try? await reservations.reserve(base: "/home/u/x.txt") { path in
            try await ConductorUpload.remotePathExists(path, stat: stat)
        }
        XCTAssertTrue(reservations.reserved.isEmpty)
    }
}
