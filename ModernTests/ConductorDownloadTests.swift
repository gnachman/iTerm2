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

private struct FakeRemoteError: LocalizedError {
    var errorDescription: String? { "fake failure" }
}

@MainActor
final class ConductorDownloadTests: XCTestCase {
    private var directory: URL!
    private var transfers = [ConductorFileTransfer]()
    private var delegates = [FakeDownloadDelegate]()
    private var removedRemotePaths = [String]()

    override func setUp() {
        super.setUp()
        FileTransferManager.setOpensMenusForTesting(false)
        TransferrableFile.setNotificationHandlerForTesting { _, _ in }
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
                          box: TransferBox? = nil) async -> ConductorFileTransfer {
        let delegate = FakeDownloadDelegate(operations: operations)
        delegates.append(delegate)
        let path = SCPPath()
        path.path = remotePath
        path.hostname = "example.com"
        path.username = "user"
        let transfer = ConductorFileTransfer(path: path, localPath: nil, data: nil, delegate: delegate)
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
                                       if chunk.offset >= data.count {
                                           box.transfer?.stop()
                                       }
                                   }),
            box: box)
        XCTAssertEqual(transfer.status, .cancelled)
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
}
