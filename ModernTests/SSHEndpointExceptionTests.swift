//
//  SSHEndpointExceptionTests.swift
//  iTerm2
//
//  Pins how framer.py's file command exit codes become errors, and the reason a failed
//  SSH Integration transfer shows for a permission error (F-718).
//

import XCTest
@testable import iTerm2SharedARC

final class SSHEndpointExceptionTests: XCTestCase {
    func testFramerExitCodes() {
        XCTAssertNil(SSHEndpointException.forFramerExitCode(0))
        XCTAssertEqual(SSHEndpointException.forFramerExitCode(-1), .connectionClosed)
        XCTAssertEqual(SSHEndpointException.forFramerExitCode(1), .permissionDenied)
        XCTAssertEqual(SSHEndpointException.forFramerExitCode(2), .fileNotFound)
        XCTAssertEqual(SSHEndpointException.forFramerExitCode(3), .notADirectory)
        XCTAssertEqual(SSHEndpointException.forFramerExitCode(4), .fileOperationFailed)
        XCTAssertEqual(SSHEndpointException.forFramerExitCode(100), .fileOperationFailed)
        XCTAssertEqual(SSHEndpointException.forFramerExitCode(255), .fileOperationFailed)
    }

    // F-718: a download of an unreadable file said only that the operation failed.
    func testDownloadPermissionDeniedReason() {
        XCTAssertEqual(
            SSHEndpointException.transferFailureReason(for: SSHEndpointException.permissionDenied,
                                                       isDownload: true),
            "The file couldn’t be read because you don’t have permission to read it on the remote host.")
    }

    // F-718: an upload into a read-only folder said only that the operation failed.
    func testUploadPermissionDeniedReason() {
        XCTAssertEqual(
            SSHEndpointException.transferFailureReason(for: SSHEndpointException.permissionDenied,
                                                       isDownload: false),
            "The file couldn’t be saved because you don’t have permission to write to the destination folder on the remote host.")
    }

    func testOtherErrorsUseTheirOwnDescription() {
        XCTAssertEqual(
            SSHEndpointException.transferFailureReason(for: SSHEndpointException.notADirectory,
                                                       isDownload: true),
            "Part of the path on the remote host is not a folder.")
        XCTAssertEqual(
            SSHEndpointException.transferFailureReason(for: SSHEndpointException.fileOperationFailed,
                                                       isDownload: false),
            "The file operation failed on the remote host")
        XCTAssertEqual(
            SSHEndpointException.transferFailureReason(for: SSHEndpointException.fileNotFound,
                                                       isDownload: true),
            "File not found")
    }
}
