//
//  ConductorChunkedDownloadTests.swift
//  iTerm2
//
//  F-714: a file fetched over SSH Integration through the file panel (Shell > ssh >
//  Download Files…, or attaching a remote file) is listed in the Downloads menu while it
//  transfers. The panel saves it itself, so the transfer was never told it finished: it
//  stayed listed as “Downloading… 20 MB of 20 MB”. Clear All didn't remove any finished SSH
//  Integration download either: once finished, it no longer counted as a download.
//

import XCTest
@testable import iTerm2SharedARC

private final class NullFileTransferDelegate: ConductorFileTransferDelegate {
    func beginDownload(fileTransfer: ConductorFileTransfer) {}
    func beginUpload(fileTransfer: ConductorFileTransfer) {}
}

@MainActor
final class ConductorChunkedDownloadTests: XCTestCase {
    // The transfer holds its delegate weakly.
    private let delegate = NullFileTransferDelegate()
    private var directory: URL!
    private var transfers = [ConductorFileTransfer]()

    override func setUp() {
        super.setUp()
        FileTransferManager.setOpensMenusForTesting(false)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        // Clear All, as a user would, so nothing is left in the Downloads menu.
        FileTransferManager.sharedInstance().removeAllDownloads()
        for transfer in transfers {
            FileTransferManager.sharedInstance().files.remove(transfer)
        }
        transfers = []
        try? FileManager.default.removeItem(at: directory)
        FileTransferManager.setOpensMenusForTesting(true)
        super.tearDown()
    }

    private func startTransfer() -> ConductorFileTransfer {
        let path = SCPPath()
        path.path = "/home/user/big.bin"
        path.hostname = "example.com"
        path.username = "user"
        let transfer = ConductorFileTransfer(path: path, localPath: nil, data: nil, delegate: delegate)
        transfer.fileSize = 5
        XCTAssertTrue(transfer.downloadChunked())
        transfers.append(transfer)
        return transfer
    }

    func testFinishedChunkedDownloadIsListedAsFinished() throws {
        let transfer = startTransfer()
        XCTAssertEqual(transfer.status, TransferrableFileStatus.transferring)
        let destination = directory.appendingPathComponent("big.bin")
        try Data("hello".utf8).write(to: destination)

        transfer.didFinishChunkedDownload(to: destination)

        XCTAssertEqual(transfer.status, TransferrableFileStatus.finishedSuccessfully)
        XCTAssertEqual(transfer.destination(), destination.path)
        XCTAssertEqual(transfer.bytesTransferred, 5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))

        // Clear All removes it.
        let manager = FileTransferManager.sharedInstance()!
        XCTAssertTrue(manager.isListingTransferrableFile(forTesting: transfer))
        manager.removeAllDownloads()
        XCTAssertFalse(manager.isListingTransferrableFile(forTesting: transfer))
    }

    func testFailedChunkedDownloadIsListedAsFailed() {
        let transfer = startTransfer()
        transfer.fail(reason: "connection lost")
        XCTAssertEqual(transfer.status, TransferrableFileStatus.finishedWithError)
    }
}
