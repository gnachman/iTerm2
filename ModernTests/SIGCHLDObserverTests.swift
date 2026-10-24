//
//  SIGCHLDObserverTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

final class SIGCHLDObserverTests: XCTestCase {
    func testChildExitIsObserved() throws {
        let registered = expectation(description: "Registered")
        let observed = expectation(description: "SIGCHLD observed")
        observed.assertForOverFulfill = false
        // Other tests' children may exit meanwhile, so this only checks that ours is seen at all.
        let observer = SIGCHLDObserver(queue: DispatchQueue(label: "test"),
                                       registered: { registered.fulfill() }) { _ in
            observed.fulfill()
        }
        // A signal delivered before registration is never reported.
        wait(for: [registered], timeout: 10)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        wait(for: [observed], timeout: 10)
        withExtendedLifetime(observer) {}
    }

    // Observing must not install a handler: SIGCHLD keeps whatever disposition it had.
    func testDispositionIsUnchanged() {
        var before = sigaction()
        XCTAssertEqual(sigaction(SIGCHLD, nil, &before), 0)
        let observer = SIGCHLDObserver(queue: DispatchQueue(label: "test")) { _ in }
        var after = sigaction()
        XCTAssertEqual(sigaction(SIGCHLD, nil, &after), 0)
        XCTAssertEqual(unsafeBitCast(before.__sigaction_u.__sa_handler, to: Int.self),
                       unsafeBitCast(after.__sigaction_u.__sa_handler, to: Int.self))
        XCTAssertEqual(before.sa_flags, after.sa_flags)
        withExtendedLifetime(observer) {}
    }
}
