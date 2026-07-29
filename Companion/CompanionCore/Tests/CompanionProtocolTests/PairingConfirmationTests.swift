//
//  PairingConfirmationTests.swift
//  CompanionCore
//
//  The first frame on a fresh pairing's encrypted channel: the mac's verdict
//  after the user types (or declines to type) the SAS code. It must round-trip
//  exactly and decode nothing else, since a garbled or unexpected first frame
//  must read as "not confirmed", never as acceptance.
//

import XCTest
@testable import CompanionProtocol

final class PairingConfirmationTests: XCTestCase {
    func testRoundTrip() {
        XCTAssertEqual(PairingConfirmation.decode(PairingConfirmation.accepted.encoded()), .accepted)
        XCTAssertEqual(PairingConfirmation.decode(PairingConfirmation.rejected.encoded()), .rejected)
    }

    func testDecodeRejectsGarbage() {
        XCTAssertNil(PairingConfirmation.decode(Data()))
        XCTAssertNil(PairingConfirmation.decode(Data("hello".utf8)))
        XCTAssertNil(PairingConfirmation.decode(Data("{\"pairing\":\"maybe\"}".utf8)))
        XCTAssertNil(PairingConfirmation.decode(Data("{\"other\":\"accepted\"}".utf8)))
        // An RPC frame from a reconnect must never decode as a confirmation.
        XCTAssertNil(PairingConfirmation.decode(Data("{\"method\":\"listChats\",\"id\":1}".utf8)))
    }
}
