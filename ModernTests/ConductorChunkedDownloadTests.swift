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
    private var notifications = [(title: String, detail: String?)]()

    override func setUp() {
        super.setUp()
        FileTransferManager.setOpensMenusForTesting(false)
        notifications = []
        TransferrableFile.setNotificationHandlerForTesting { [weak self] title, detail in
            self?.notifications.append((title: title, detail: detail))
        }
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
        TransferrableFile.setNotificationHandlerForTesting(nil)
        super.tearDown()
    }

    private func startTransfer(hostname: String = "example.com") -> ConductorFileTransfer {
        let path = SCPPath()
        path.path = "/home/user/big.bin"
        path.hostname = hostname
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

    // F-1051: Get Info on a failed download said “Destination: /home/user/big.bin”, the remote
    // source path, as if that were where the file was saved.
    func testFailedDownloadHasNoDestination() {
        let transfer = startTransfer()
        transfer.fail(reason: "File not found")
        XCTAssertNil(transfer.destination())
        // Nor its deleted hidden temporary file as its local path.
        XCTAssertNil(transfer.localPath())
    }

    func testStoppedDownloadHasNoDestination() {
        let transfer = startTransfer()
        transfer.stop()
        XCTAssertNil(transfer.destination())
        XCTAssertNil(transfer.localPath())
    }

    func testFailedChunkedDownloadIsListedAsFailed() {
        let transfer = startTransfer()
        transfer.fail(reason: "connection lost")
        XCTAssertEqual(transfer.status, TransferrableFileStatus.finishedWithError)
    }

    // F-717: the notification named neither the file nor that the download failed. It was just
    // the bare reason, such as “File not found”.
    func testFailedChunkedDownloadNotificationNamesFileAndReason() {
        let transfer = startTransfer()
        transfer.fail(reason: "File not found")
        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications.first?.title, "Download failed for “big.bin”.")
        XCTAssertEqual(notifications.first?.detail, "File not found")
    }

    func testFinishedChunkedDownloadNotification() throws {
        let transfer = startTransfer()
        let destination = directory.appendingPathComponent("big.bin")
        try Data("hello".utf8).write(to: destination)
        transfer.didFinishChunkedDownload(to: destination)
        XCTAssertEqual(notifications.map(\.title), ["Download finished for “big.bin”."])
    }

    // F-721: a folder download that left out files it couldn't read finishes, but says so.
    func testFinishedDownloadNotificationIncludesCompletionNote() throws {
        let transfer = startTransfer()
        transfer.completionNote = "“secret” couldn’t be read and was left out."
        let destination = directory.appendingPathComponent("big.bin")
        try Data("hello".utf8).write(to: destination)
        transfer.didFinishChunkedDownload(to: destination)
        XCTAssertEqual(transfer.status, TransferrableFileStatus.finishedSuccessfully)
        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications.first?.title, "Download finished for “big.bin”.")
        XCTAssertEqual(notifications.first?.detail, "“secret” couldn’t be read and was left out.")
    }

    func testFinishedDownloadNotificationHasNoDetailWithoutNote() throws {
        let transfer = startTransfer()
        let destination = directory.appendingPathComponent("big.bin")
        try Data("hello".utf8).write(to: destination)
        transfer.didFinishChunkedDownload(to: destination)
        XCTAssertEqual(notifications.count, 1)
        XCTAssertNil(notifications.first?.detail)
    }

    // Stopping a download is not a failure, so it posts no notification.
    func testStoppedChunkedDownloadPostsNoNotification() {
        let transfer = startTransfer()
        transfer.abort()
        XCTAssertEqual(transfer.status, TransferrableFileStatus.cancelled)
        XCTAssertTrue(notifications.isEmpty)
    }

    // F-920: a host that can't go in a URL, such as “qa@127.0.0.1” from `it2ssh qa@127.0.0.1`,
    // crashed when the download finished because the quarantine source URL was force-unwrapped.
    func testFinishedChunkedDownloadWithHostThatIsNotAValidURLHost() throws {
        for hostname in ["qa@127.0.0.1", "bad host/with:stuff"] {
            let transfer = startTransfer(hostname: hostname)
            let destination = directory.appendingPathComponent(UUID().uuidString)
            try Data("hello".utf8).write(to: destination)
            transfer.didFinishChunkedDownload(to: destination)
            XCTAssertEqual(transfer.status, TransferrableFileStatus.finishedSuccessfully, hostname)
        }
    }
}
