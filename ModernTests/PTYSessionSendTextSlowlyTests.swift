//
//  PTYSessionSendTextSlowlyTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class PTYSessionSendTextSlowlyTests: XCTestCase {
    // QA finding F-542: PTYSession is manual retain/release and kept the table of slowly
    // sent pastes without retaining it, so it was freed when the autorelease pool drained
    // and the next send messaged a dead object.
    func testSlowlySentPasteTableOutlivesAutoreleasePool() {
        let session = PTYSession(synthetic: false)!
        autoreleasepool {
            session.sendTextSlowly("echo one\n")
        }
        autoreleasepool {
            session.sendTextSlowly("echo two\n")
        }
        autoreleasepool {
            session.stopSendingTextSlowly()
        }
        session.sendTextSlowly("echo three\n")
        session.stopSendingTextSlowly()
    }
}
