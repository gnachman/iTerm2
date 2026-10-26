//
//  TransferCancellationNotificationTests.swift
//  iTerm2
//
//  A transfer the user cancels (the save panel of an inline download, or declining to
//  connect to a new host for an SCP transfer) used to be reported as a failure, so its
//  notification read “Download failed for “…”.” with “Canceled.” as the reason. A
//  cancellation is listed as canceled and posts no notification.
//

import XCTest
@testable import iTerm2SharedARC

private final class IgnoringFileTransferDelegate: ConductorFileTransferDelegate {
    func beginDownload(fileTransfer: ConductorFileTransfer) {}
    func beginUpload(fileTransfer: ConductorFileTransfer) {}
}

@MainActor
final class TransferCancellationNotificationTests: XCTestCase, iTermWarningHandler {
    // The transfer holds its delegate weakly.
    private let delegate = IgnoringFileTransferDelegate()
    private var notifications = [(title: String, detail: String?)]()
    private var transfers = [TransferrableFile]()
    private var warningIdentifiers = [String?]()

    override func setUp() {
        super.setUp()
        FileTransferManager.setOpensMenusForTesting(false)
        notifications = []
        warningIdentifiers = []
        TransferrableFile.setNotificationHandlerForTesting { [weak self] title, detail in
            self?.notifications.append((title: title, detail: detail))
        }
        iTermWarning.setWarningHandler(self)
    }

    override func tearDown() {
        // +[iTermWarning setWarningHandler:] is declared nonnull, but nil restores real alerts.
        _ = (iTermWarning.self as AnyObject).perform(#selector(iTermWarning.setWarningHandler(_:)), with: nil)
        let manager = FileTransferManager.sharedInstance()!
        manager.removeAllDownloads()
        manager.removeAllUploads()
        for transfer in transfers {
            manager.files.remove(transfer)
        }
        transfers = []
        TransferrableFile.setNotificationHandlerForTesting(nil)
        FileTransferManager.setOpensMenusForTesting(true)
        super.tearDown()
    }

    // MARK: - iTermWarningHandler

    // Every warning these tests raise asks whether to connect to a new host. Answer Cancel.
    func warningWouldShow(_ alert: NSAlert, identifier: String?) -> NSApplication.ModalResponse {
        warningIdentifiers.append(identifier)
        return .alertSecondButtonReturn
    }

    // MARK: - Helpers

    private func scpFile() -> SCPFile {
        let path = SCPPath()
        // A host nobody has agreed to connect to, so the transfer asks first.
        path.hostname = "f717-\(UUID().uuidString).example.com"
        path.username = "user"
        path.path = "/home/user/report.txt"
        let file = SCPFile()
        file.path = path
        transfers.append(file)
        return file
    }

    // MARK: - Tests

    func testCanceledSavePanelIsCanceledWithoutNotification() {
        // A nil local path is what the save panel leaves when the user cancels it. The panel
        // itself can't run in a test, so clear the path the way canceling it would.
        let file = TerminalFile(name: "f717-\(UUID().uuidString).txt", size: 5)!
        file.setValue(nil, forKey: "localPath")
        transfers.append(file)

        file.download()

        XCTAssertEqual(file.status, TransferrableFileStatus.cancelled)
        XCTAssertTrue(notifications.isEmpty, "\(notifications)")

        // Data that still arrives is dropped and the transfer stays canceled.
        XCTAssertTrue(file.appendData("aGVsbG8="))
        file.endOfData()
        XCTAssertEqual(file.status, TransferrableFileStatus.cancelled)
        XCTAssertTrue(notifications.isEmpty, "\(notifications)")
    }

    func testTerminalFileShortNameFallsBackToSuggestedName() {
        let file = TerminalFile(name: "notes-\(UUID().uuidString).txt", size: 5)!
        let name = file.shortName()
        transfers.append(file)
        file.setValue(nil, forKey: "localPath")
        XCTAssertEqual(file.shortName(), name)
    }

    func testDecliningToConnectCancelsSCPDownloadWithoutNotification() {
        let file = scpFile()
        file.download()
        XCTAssertEqual(warningIdentifiers.count, 1)
        XCTAssertEqual(file.status, TransferrableFileStatus.cancelled)
        XCTAssertTrue(notifications.isEmpty, "\(notifications)")
    }

    func testDecliningToConnectCancelsSCPUploadWithoutNotification() throws {
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("f717-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: local)
        defer {
            try? FileManager.default.removeItem(at: local)
        }
        let file = scpFile()
        // Swift sees the inherited localPath() method rather than this property.
        file.setValue(local.path, forKey: "localPath")
        file.upload()
        XCTAssertEqual(warningIdentifiers.count, 1)
        XCTAssertEqual(file.status, TransferrableFileStatus.cancelled)
        XCTAssertTrue(notifications.isEmpty, "\(notifications)")
    }

    // An error reported after the user stopped a transfer is how stopping ended it, not a
    // failure.
    func testErrorAfterStopIsCancellation() {
        let path = SCPPath()
        path.path = "/home/user/big.bin"
        path.hostname = "example.com"
        path.username = "user"
        let transfer = ConductorFileTransfer(path: path, localPath: nil, data: nil, delegate: delegate)
        transfer.fileSize = 5
        XCTAssertTrue(transfer.downloadChunked())
        transfers.append(transfer)

        transfer.stop()
        XCTAssertEqual(transfer.status, TransferrableFileStatus.cancelling)
        transfer.fail(reason: "connection reset")

        XCTAssertEqual(transfer.status, TransferrableFileStatus.cancelled)
        XCTAssertTrue(notifications.isEmpty, "\(notifications)")
    }
}
