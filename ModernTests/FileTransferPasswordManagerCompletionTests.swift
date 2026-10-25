//
//  FileTransferPasswordManagerCompletionTests.swift
//  ModernTests
//
//  An scp transfer that asks for its password can hand the request to the
//  password manager. The transfer thread blocks until the completion runs, so
//  closing the password manager must cancel the request (call the completion
//  with nil), and the completion must never run twice.
//

import XCTest
@testable import iTerm2SharedARC

final class FileTransferPasswordManagerCompletionTests: XCTestCase {
    private var calls: [String?] = []

    private func makeManager() -> FileTransferManager {
        let manager = FileTransferManager()
        manager.setPasswordManagerCompletionForTesting { [unowned self] password in
            self.calls.append(password)
        }
        return manager
    }

    func testClosingThePasswordManagerCancelsTheRequest() {
        let manager = makeManager()
        manager.iTermPasswordManagerDidClose()
        XCTAssertEqual(calls, [nil])
    }

    func testChoosingAPasswordGivesItToTheTransfer() {
        let manager = makeManager()
        manager.iTermPasswordManagerEnterPassword("hunter2", broadcast: false)
        XCTAssertEqual(calls, ["hunter2"])
    }

    func testCloseAfterChoosingDoesNotCallAgain() {
        let manager = makeManager()
        manager.iTermPasswordManagerEnterPassword("hunter2", broadcast: false)
        manager.iTermPasswordManagerDidClose()
        XCTAssertEqual(calls, ["hunter2"])
    }

    func testClosingTwiceCallsOnce() {
        let manager = makeManager()
        manager.iTermPasswordManagerDidClose()
        manager.iTermPasswordManagerDidClose()
        XCTAssertEqual(calls, [nil])
    }
}
