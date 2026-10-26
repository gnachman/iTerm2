//
//  ConductorDownloadTests.swift
//  iTerm2
//
//  F-724: a download from “Download using SSH Integration” saves to a hidden file
//  ~/Downloads/.iTerm2.<UUID> until it finishes. A folder download that failed before the
//  transfer started (the folder couldn't be listed, a mistyped name, the remote home not
//  writable) left that file behind, empty, every time.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
private final class FakeDownloadDelegate: ConductorFileTransferDelegate {
    var operations: ConductorDownloadOperations
    var task: Task<Void, Never>?

    init(operations: ConductorDownloadOperations) {
        self.operations = operations
    }

    func beginDownload(fileTransfer: ConductorFileTransfer) {
        let operations = self.operations
        task = Task { @MainActor in
            await ConductorDownload.run(fileTransfer: fileTransfer, operations: operations)
        }
    }

    func beginUpload(fileTransfer: ConductorFileTransfer) {}
}

// Lets a fake operation reach the transfer it is serving.
@MainActor
private final class TransferBox {
    weak var transfer: ConductorFileTransfer?
}

// Fails the local steps that follow a finished download: quarantining the file, or moving
// it into place.
@MainActor
private final class LocalFailureTransfer: ConductorFileTransfer {
    var quarantineHandler: ((String?) -> Bool)?
    var destinationDirectory: String?

    override func quarantine(_ path: String?, sourceURL: URL?) -> Bool {
        if let quarantineHandler {
            return quarantineHandler(path)
        }
        return super.quarantine(path, sourceURL: sourceURL)
    }

    override func finalDestination(forPath baseName: String,
                                   destinationDirectory: String,
                                   prompt: Bool) -> String? {
        return super.finalDestination(forPath: baseName,
                                      destinationDirectory: self.destinationDirectory ?? destinationDirectory,
                                      prompt: prompt)
    }
}

private struct FakeRemoteError: LocalizedError {
    var errorDescription: String? { "fake failure" }
}

@MainActor
final class ConductorDownloadTests: XCTestCase {
    private var directory: URL!
    private var transfers = [ConductorFileTransfer]()
    private var delegates = [FakeDownloadDelegate]()
    private var removedRemotePaths = [String]()
    private var notificationTitles = [String]()

    override func setUp() {
        super.setUp()
        FileTransferManager.setOpensMenusForTesting(false)
        notificationTitles = []
        TransferrableFile.setNotificationHandlerForTesting { [weak self] title, _ in
            MainActor.assumeIsolated {
                self?.notificationTitles.append(title)
            }
        }
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        ConductorFileTransfer.temporaryDirectoryForTesting = directory.path
        removedRemotePaths = []
    }

    override func tearDown() {
        for transfer in transfers {
            FileTransferManager.sharedInstance().files.remove(transfer)
        }
        transfers = []
        delegates = []
        ConductorFileTransfer.temporaryDirectoryForTesting = nil
        try? FileManager.default.removeItem(at: directory)
        FileTransferManager.setOpensMenusForTesting(true)
        TransferrableFile.setNotificationHandlerForTesting(nil)
        super.tearDown()
    }

    private func contentsOfDirectory() throws -> [String] {
        return try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    private func operations(files: [String: Data] = [:],
                            folders: Set<String> = [],
                            zip: @escaping (String) throws -> SSHRemoteZipReply = { _ in throw FakeRemoteError() },
                            beforeFetch: @escaping (DownloadChunk) throws -> Void = { _ in }) -> ConductorDownloadOperations {
        return ConductorDownloadOperations(
            stat: { path in
                if folders.contains(path) {
                    return RemoteFile(kind: .folder, absolutePath: path)
                }
                guard let data = files[path] else {
                    throw SSHEndpointException.fileNotFound
                }
                return RemoteFile(kind: .file(.init(size: data.count)), absolutePath: path)
            },
            zip: { path in try zip(path) },
            fetch: { path, chunk in
                try beforeFetch(chunk)
                guard let data = files[path] else {
                    throw SSHEndpointException.fileNotFound
                }
                let start = min(chunk.offset, data.count)
                let end = min(chunk.offset + chunk.size, data.count)
                return data.subdata(in: start..<end)
            },
            rm: { [weak self] path in
                self?.removedRemotePaths.append(path)
            })
    }

    private func download(_ remotePath: String,
                          operations: ConductorDownloadOperations,
                          box: TransferBox? = nil,
                          makeTransfer: ((SCPPath, ConductorFileTransferDelegate) -> ConductorFileTransfer)? = nil) async -> ConductorFileTransfer {
        let delegate = FakeDownloadDelegate(operations: operations)
        delegates.append(delegate)
        let path = SCPPath()
        path.path = remotePath
        path.hostname = "example.com"
        path.username = "user"
        let transfer = makeTransfer?(path, delegate)
            ?? ConductorFileTransfer(path: path, localPath: nil, data: nil, delegate: delegate)
        transfers.append(transfer)
        box?.transfer = transfer
        transfer.download()
        await delegate.task?.value
        return transfer
    }

    private func bytes(_ count: Int) -> Data {
        return Data((0..<count).map { UInt8(truncatingIfNeeded: $0 * 7) })
    }

    // The reported case: zip fails (the folder can't be listed or the remote home isn't
    // writable).
    func testFailedZipLeavesNoFile() async throws {
        let transfer = await download("/home/user/dir",
                                      operations: operations(folders: ["/home/user/dir"]))
        XCTAssertEqual(transfer.status, .finishedWithError)
        XCTAssertEqual(try contentsOfDirectory(), [])
    }

    // A mistyped name.
    func testMissingRemoteFileLeavesNoFile() async throws {
        let transfer = await download("/home/user/nope", operations: operations())
        XCTAssertEqual(transfer.status, .finishedWithError)
        XCTAssertEqual(try contentsOfDirectory(), [])
    }

    func testFailureMidDownloadLeavesNoPartialFile() async throws {
        let transfer = await download(
            "/home/user/big.bin",
            operations: operations(files: ["/home/user/big.bin": bytes(10_000)],
                                   beforeFetch: { chunk in
                                       if chunk.offset > 0 {
                                           throw SSHEndpointException.connectionClosed
                                       }
                                   }))
        XCTAssertEqual(transfer.status, .finishedWithError)
        XCTAssertEqual(try contentsOfDirectory(), [])
    }

    func testStoppedDownloadLeavesNoPartialFile() async throws {
        let box = TransferBox()
        let transfer = await download(
            "/home/user/big.bin",
            operations: operations(files: ["/home/user/big.bin": bytes(10_000)],
                                   beforeFetch: { chunk in
                                       if chunk.offset > 0 {
                                           box.transfer?.stop()
                                       }
                                   }),
            box: box)
        XCTAssertEqual(transfer.status, .cancelled)
        XCTAssertEqual(try contentsOfDirectory(), [])
    }

    // Stopped during the request that turns out to be the last one.
    func testStoppedDuringLastRequestLeavesNoFile() async throws {
        let box = TransferBox()
        let data = bytes(100)
        let transfer = await download(
            "/home/user/small.bin",
            operations: operations(files: ["/home/user/small.bin": data],
                                   beforeFetch: { chunk in
                                       if chunk.offset + chunk.size >= data.count {
                                           box.transfer?.stop()
                                       }
                                   }),
            box: box)
        XCTAssertEqual(transfer.status, .cancelled)
        XCTAssertEqual(try contentsOfDirectory(), [])
    }

    // Stopped while zip runs, which then fails: it ends as stopped, not failed.
    func testStoppedDuringFailingZipEndsAsStopped() async throws {
        let box = TransferBox()
        let transfer = await download(
            "/home/user/dir",
            operations: operations(folders: ["/home/user/dir"],
                                   zip: { _ in
                                       box.transfer?.stop()
                                       throw FakeRemoteError()
                                   }),
            box: box)
        XCTAssertEqual(transfer.status, .cancelled)
        XCTAssertEqual(try contentsOfDirectory(), [])
    }

    // Stopped while the folder is examined: it isn't zipped.
    func testStoppedBeforeZipDoesNotZip() async throws {
        let box = TransferBox()
        var zips = 0
        var ops = operations(folders: ["/home/user/dir"],
                             zip: { _ in
                                 zips += 1
                                 return SSHRemoteZipReply(path: "/home/user/dir.zip")
                             })
        let realStat = ops.stat
        ops.stat = { path in
            box.transfer?.stop()
            return try await realStat(path)
        }
        let transfer = await download("/home/user/dir", operations: ops, box: box)
        XCTAssertEqual(transfer.status, .cancelled)
        XCTAssertEqual(zips, 0)
        XCTAssertEqual(try contentsOfDirectory(), [])
    }

    // A zip reply that names a folder fails without downloading anything.
    func testZipThatIsAFolderFailsAndLeavesNoFile() async throws {
        var fetches = 0
        let transfer = await download(
            "/home/user/dir",
            operations: operations(folders: ["/home/user/dir", "/home/user/dir.zip"],
                                   zip: { _ in SSHRemoteZipReply(path: "/home/user/dir.zip") },
                                   beforeFetch: { _ in fetches += 1 }))
        XCTAssertEqual(transfer.status, .finishedWithError)
        XCTAssertEqual(fetches, 0)
        XCTAssertEqual(try contentsOfDirectory(), [])
    }

    func testFinishedDownloadLeavesOnlyTheFile() async throws {
        let data = bytes(10_000)
        let transfer = await download("/home/user/big.bin",
                                      operations: operations(files: ["/home/user/big.bin": data]))
        XCTAssertEqual(transfer.status, .finishedSuccessfully)
        XCTAssertEqual(try contentsOfDirectory(), ["big.bin"])
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("big.bin")), data)
    }

    func testFinishedFolderDownloadLeavesOnlyTheArchive() async throws {
        let data = bytes(5_000)
        let transfer = await download(
            "/home/user/dir",
            operations: operations(files: ["/home/user/.iterm2-dir.zip": data],
                                   folders: ["/home/user/dir"],
                                   zip: { _ in SSHRemoteZipReply(path: "/home/user/.iterm2-dir.zip") }))
        XCTAssertEqual(transfer.status, .finishedSuccessfully)
        XCTAssertEqual(try contentsOfDirectory(), ["dir.zip"])
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("dir.zip")), data)
        XCTAssertEqual(removedRemotePaths, ["/home/user/.iterm2-dir.zip"])
    }

    // F-725: this kind of download asked for 1 KiB at a time and waited for each reply before
    // asking for the next, so a 12 MB folder archive took 17 minutes over a connection that
    // moves a file fetched through the file panel (4 KiB requests, 8 at a time) 30 times faster.
    func testDownloadUsesTheSameChunksAsTheFilePanel() async throws {
        let data = bytes(100_000)
        var chunks = [DownloadChunk]()
        let transfer = await download("/home/user/big.bin",
                                      operations: operations(files: ["/home/user/big.bin": data],
                                                             beforeFetch: { chunks.append($0) }))
        XCTAssertEqual(transfer.status, .finishedSuccessfully)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("big.bin")), data)
        XCTAssertEqual(ConductorDownload.chunkSize, 4096)
        XCTAssertTrue(chunks.allSatisfy { $0.size == ConductorDownload.chunkSize })
        // One request per chunk; the last one is short, so no request past the end is needed.
        XCTAssertEqual(chunks.count, (data.count + ConductorDownload.chunkSize - 1) / ConductorDownload.chunkSize)
        XCTAssertEqual(chunks.map(\.offset), Array(stride(from: 0, to: data.count, by: ConductorDownload.chunkSize)))
    }

    func testFolderArchiveUsesTheSameChunksAsTheFilePanel() async throws {
        let data = bytes(50_000)
        var chunks = [DownloadChunk]()
        let transfer = await download(
            "/home/user/dir",
            operations: operations(files: ["/home/user/.iterm2-dir.zip": data],
                                   folders: ["/home/user/dir"],
                                   zip: { _ in SSHRemoteZipReply(path: "/home/user/.iterm2-dir.zip") },
                                   beforeFetch: { chunks.append($0) }))
        XCTAssertEqual(transfer.status, .finishedSuccessfully)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("dir.zip")), data)
        XCTAssertTrue(chunks.allSatisfy { $0.size == ConductorDownload.chunkSize })
        XCTAssertEqual(chunks.count, (data.count + ConductorDownload.chunkSize - 1) / ConductorDownload.chunkSize)
    }

    // A file whose size is a multiple of the chunk size ends with an empty reply.
    func testDownloadOfExactMultipleOfChunkSize() async throws {
        let data = bytes(ConductorDownload.chunkSize * 3)
        var chunks = [DownloadChunk]()
        let transfer = await download("/home/user/big.bin",
                                      operations: operations(files: ["/home/user/big.bin": data],
                                                             beforeFetch: { chunks.append($0) }))
        XCTAssertEqual(transfer.status, .finishedSuccessfully)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("big.bin")), data)
        XCTAssertEqual(chunks.count, 4)
    }

    func testEmptyFile() async throws {
        let transfer = await download("/home/user/empty",
                                      operations: operations(files: ["/home/user/empty": Data()]))
        XCTAssertEqual(transfer.status, .finishedSuccessfully)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("empty")), Data())
    }

    // Several requests are in flight at once rather than one round trip per chunk.
    func testRequestsArePipelined() async throws {
        let data = bytes(ConductorDownload.chunkSize * 20 + 5)
        var inFlight = 0
        var maximumInFlight = 0
        var received = Data()
        let finished = try await ConductorDownload.fetch(expectedSize: data.count,
                                                         isStopped: { false },
                                                         fetch: { chunk in
            inFlight += 1
            maximumInFlight = max(maximumInFlight, inFlight)
            await Task.yield()
            inFlight -= 1
            let start = min(chunk.offset, data.count)
            return data.subdata(in: start..<min(chunk.offset + chunk.size, data.count))
        }, consume: { received.append($0) })
        XCTAssertTrue(finished)
        XCTAssertEqual(received, data)
        XCTAssertGreaterThan(maximumInFlight, 1)
        XCTAssertLessThanOrEqual(maximumInFlight, ConductorDownload.maxRequestsInFlight)
    }

    // The size isn't always known, and a file can grow after it was examined.
    func testUnknownSizeAndGrownFileAreReadToTheEnd() async throws {
        let data = bytes(ConductorDownload.chunkSize * 5 + 17)
        for expectedSize in [nil, ConductorDownload.chunkSize, 0] {
            var received = Data()
            let finished = try await ConductorDownload.fetch(expectedSize: expectedSize,
                                                             isStopped: { false },
                                                             fetch: { chunk in
                let start = min(chunk.offset, data.count)
                return data.subdata(in: start..<min(chunk.offset + chunk.size, data.count))
            }, consume: { received.append($0) })
            XCTAssertTrue(finished)
            XCTAssertEqual(received, data, "expectedSize \(String(describing: expectedSize))")
        }
    }

    private func localFailureTransfer(_ configure: @escaping (LocalFailureTransfer) -> Void) -> (SCPPath, ConductorFileTransferDelegate) -> ConductorFileTransfer {
        return { path, delegate in
            let transfer = LocalFailureTransfer(path: path, localPath: nil, data: nil, delegate: delegate)
            configure(transfer)
            return transfer
        }
    }

    private var downloadFinishedNotifications: [String] {
        return notificationTitles.filter { $0.hasPrefix("Download finished") }
    }

    // T-180: when the finished file couldn't be moved into place, the transfer still reported
    // success, said it was saved, and pointed at a file that didn't exist.
    func testFailedMoveIntoPlaceFailsAndLeavesNoFile() async throws {
        let missing = directory.appendingPathComponent("missing").path
        let transfer = await download(
            "/home/user/big.bin",
            operations: operations(files: ["/home/user/big.bin": bytes(10_000)]),
            makeTransfer: localFailureTransfer { $0.destinationDirectory = missing })
        XCTAssertEqual(transfer.status, .finishedWithError)
        XCTAssertTrue(transfer.isStopped)
        XCTAssertFalse(transfer.error()?.isEmpty ?? true)
        XCTAssertEqual(downloadFinishedNotifications, [])
        XCTAssertEqual(notificationTitles.count, 1)
        XCTAssertEqual(try contentsOfDirectory(), [])
    }
}
